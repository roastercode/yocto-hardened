// SPDX-License-Identifier: GPL-2.0-only
/*
 * ftrfsd — FTRFS Radiation Event Journal daemon
 *
 * Reads the RAF (Radiation Event Journal) from a FTRFS superblock
 * and logs correction events to syslog.
 *
 * Usage: ftrfsd <device>
 *   e.g. ftrfsd /dev/vdb
 *
 * The RAF is a ring buffer of 64 ftrfs_rs_event entries stored in
 * the superblock at block 0. Each entry is 24 bytes:
 *   re_block_no   (8)  — corrected block number
 *   re_timestamp  (8)  — nanoseconds since boot
 *   re_error_bits (4)  — number of symbols corrected
 *   re_crc32      (4)  — CRC32 of this entry
 *
 * Author: Aurelien DESBRIERES <aurelien@hackers.camp>
 * Assisted-by: Claude <claude-sonnet-4-6>
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <syslog.h>
#include <signal.h>
#include <errno.h>
#include <time.h>

/* Must match ftrfs.h exactly */
#define FTRFS_MAGIC          0x46545246U
#define FTRFS_RS_JOURNAL_SIZE 64
#define FTRFS_SB_SIZE        4096
#define FTRFS_RS_JOURNAL_OFF 120   /* offset of s_rs_journal in superblock */
#define FTRFS_RS_HEAD_OFF    1656  /* offset of s_rs_journal_head */
#define FTRFS_POLL_INTERVAL  5     /* seconds between superblock reads */

#pragma pack(push, 1)
struct ftrfs_rs_event {
	uint64_t re_block_no;
	uint64_t re_timestamp;
	uint32_t re_error_bits;
	uint32_t re_crc32;
}; /* 24 bytes */
#pragma pack(pop)

static volatile int running = 1;

static void handle_sig(int sig)
{
	(void)sig;
	running = 0;
}

/*
 * crc32 — standard CRC-32/ISO-HDLC
 * Seed and final XOR 0xFFFFFFFF, poly 0xEDB88320 (reflected 0x04C11DB7)
 */
static uint32_t crc32(const void *buf, size_t len)
{
	const uint8_t *p = buf;
	uint32_t crc = 0xFFFFFFFFU;
	size_t i, j;

	for (i = 0; i < len; i++) {
		crc ^= p[i];
		for (j = 0; j < 8; j++)
			crc = (crc >> 1) ^ ((crc & 1) ? 0xEDB88320U : 0);
	}
	return crc ^ 0xFFFFFFFFU;
}

static int entry_is_valid(const struct ftrfs_rs_event *e)
{
	uint32_t computed;

	if (e->re_block_no == 0 && e->re_timestamp == 0 &&
	    e->re_error_bits == 0)
		return 0; /* empty slot */

	computed = crc32(e, sizeof(*e) - sizeof(e->re_crc32));
	return computed == e->re_crc32;
}

static void log_event(int idx, const struct ftrfs_rs_event *e)
{
	syslog(LOG_WARNING,
	       "RAF[%02d] block=%llu ts=%llu ns symbols_corrected=%u",
	       idx,
	       (unsigned long long)e->re_block_no,
	       (unsigned long long)e->re_timestamp,
	       e->re_error_bits);

	fprintf(stderr,
		"RAF[%02d] block=%llu ts=%llu ns symbols_corrected=%u\n",
		idx,
		(unsigned long long)e->re_block_no,
		(unsigned long long)e->re_timestamp,
		e->re_error_bits);
}

int main(int argc, char *argv[])
{
	uint8_t sb[FTRFS_SB_SIZE];
	struct ftrfs_rs_event journal[FTRFS_RS_JOURNAL_SIZE];
	uint8_t  head;
	uint32_t magic;
	int fd, i;
	const char *dev;

	if (argc < 2) {
		fprintf(stderr, "Usage: ftrfsd <device>\n");
		return 1;
	}
	dev = argv[1];

	signal(SIGTERM, handle_sig);
	signal(SIGINT,  handle_sig);

	openlog("ftrfsd", LOG_PID | LOG_NDELAY, LOG_DAEMON);
	syslog(LOG_INFO, "ftrfsd starting on %s", dev);

	while (running) {
		fd = open(dev, O_RDONLY);
		if (fd < 0) {
			syslog(LOG_ERR, "open %s: %s", dev, strerror(errno));
			sleep(FTRFS_POLL_INTERVAL);
			continue;
		}

		if (read(fd, sb, FTRFS_SB_SIZE) != FTRFS_SB_SIZE) {
			syslog(LOG_ERR, "read superblock: %s", strerror(errno));
			close(fd);
			sleep(FTRFS_POLL_INTERVAL);
			continue;
		}
		close(fd);

		memcpy(&magic, sb, 4);
		if (magic != FTRFS_MAGIC) {
			syslog(LOG_ERR, "%s: bad magic 0x%08x", dev, magic);
			sleep(FTRFS_POLL_INTERVAL);
			continue;
		}

		memcpy(journal, sb + FTRFS_RS_JOURNAL_OFF, sizeof(journal));
		head = sb[FTRFS_RS_HEAD_OFF];

		for (i = 0; i < FTRFS_RS_JOURNAL_SIZE; i++) {
			if (entry_is_valid(&journal[i]))
				log_event(i, &journal[i]);
		}

		syslog(LOG_DEBUG, "RAF scan done, head=%u", head);
		sleep(FTRFS_POLL_INTERVAL);
	}

	syslog(LOG_INFO, "ftrfsd stopped");
	closelog();
	return 0;
}
