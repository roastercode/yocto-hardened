/* inject_raf.c — inject a valid RAF event into a FTRFS superblock
 * Usage: inject_raf <device> <block_no> <err_bits>
 * Writes a valid ftrfs_rs_event at the current journal head position.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <time.h>

#define FTRFS_MAGIC          0x46545246U
#define FTRFS_RS_JOURNAL_OFF 120
#define FTRFS_RS_HEAD_OFF    1656
#define FTRFS_RS_JOURNAL_SIZE 64
#define FTRFS_SB_SIZE        4096

/* little-endian helpers */
static uint64_t le64(uint64_t v) { return v; }
static uint32_t le32(uint32_t v) { return v; }

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

#pragma pack(push, 1)
struct ftrfs_rs_event {
	uint64_t re_block_no;
	uint64_t re_timestamp;
	uint32_t re_error_bits;
	uint32_t re_crc32;
};
#pragma pack(pop)

int main(int argc, char *argv[])
{
	uint8_t sb[FTRFS_SB_SIZE];
	struct ftrfs_rs_event ev;
	uint32_t magic;
	uint8_t head;
	int fd;
	uint64_t block_no;
	uint32_t err_bits;
	struct timespec ts;

	if (argc != 4) {
		fprintf(stderr, "Usage: inject_raf <device> <block_no> <err_bits>\n");
		return 1;
	}
	block_no = (uint64_t)atoll(argv[2]);
	err_bits = (uint32_t)atoi(argv[3]);

	fd = open(argv[1], O_RDWR);
	if (fd < 0) { perror("open"); return 1; }

	if (read(fd, sb, FTRFS_SB_SIZE) != FTRFS_SB_SIZE) {
		perror("read"); close(fd); return 1;
	}

	memcpy(&magic, sb, 4);
	if (magic != FTRFS_MAGIC) {
		fprintf(stderr, "bad magic: 0x%08x\n", magic);
		close(fd); return 1;
	}

	head = sb[FTRFS_RS_HEAD_OFF];
	head = head % FTRFS_RS_JOURNAL_SIZE;

	clock_gettime(CLOCK_BOOTTIME, &ts);
	uint64_t ns = (uint64_t)ts.tv_sec * 1000000000ULL + ts.tv_nsec;

	ev.re_block_no   = le64(block_no);
	ev.re_timestamp  = le64(ns);
	ev.re_error_bits = le32(err_bits);
	ev.re_crc32      = le32(crc32(&ev, 20));

	size_t off = FTRFS_RS_JOURNAL_OFF + head * sizeof(ev);
	memcpy(sb + off, &ev, sizeof(ev));

	uint8_t new_head = (head + 1) % FTRFS_RS_JOURNAL_SIZE;
	sb[FTRFS_RS_HEAD_OFF] = new_head;

	lseek(fd, 0, SEEK_SET);
	if (write(fd, sb, FTRFS_SB_SIZE) != FTRFS_SB_SIZE) {
		perror("write"); close(fd); return 1;
	}
	close(fd);

	printf("injected RAF event: block=%llu ts=%llu ns err_bits=%u at slot %u\n",
	       (unsigned long long)block_no,
	       (unsigned long long)ns,
	       err_bits, head);
	return 0;
}
