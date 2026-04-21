// SPDX-License-Identifier: GPL-2.0-only
/*
 * ftrfsd — FTRFS Radiation Event Journal daemon v2
 *
 * Reads the RAF (Radiation Event Journal) from a FTRFS superblock,
 * signs each correction event with a node-local Ed25519 key, and
 * logs the signed attestation to syslog.
 *
 * This implements the first brick of the semantic-sync trust substrate:
 * verifiable per-node event attestation without a central authority.
 *
 * Key management:
 *   - Private key: /data/ftrfsd/node.key (PEM, generated on first run)
 *   - Public key:  /data/ftrfsd/node.pub (PEM, logged at startup)
 *
 * Signed payload per event (20 bytes):
 *   re_block_no (8) || re_timestamp (8) || re_error_bits (4)
 *
 * Usage: ftrfsd <device>
 *   e.g. ftrfsd /dev/loop0
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
#include <sys/stat.h>
#include <sys/vfs.h>
#include <sys/file.h>

#include <openssl/evp.h>
#include <openssl/pem.h>
#include <openssl/err.h>

/* Must match ftrfs.h exactly */
#define FTRFS_MAGIC           0x46545246U
#define FTRFS_RS_JOURNAL_SIZE 64
#define FTRFS_SB_SIZE         4096
#define FTRFS_RS_JOURNAL_OFF  120
#define FTRFS_RS_HEAD_OFF     1656
#define FTRFS_POLL_INTERVAL   5

#define FTRFSD_KEY_DIR_PARENT "/data"
#define FTRFSD_KEY_DIR   "/data/ftrfsd"
#define FTRFSD_KEY_PRIV  "/data/ftrfsd/node.key"
#define FTRFSD_KEY_PUB   "/data/ftrfsd/node.pub"
#define FTRFSD_LOCK_FILE "/data/ftrfsd/ftrfsd.lock"
#define FTRFSD_MOUNT_TIMEOUT 30  /* max seconds to wait for FTRFS mount */

#pragma pack(push, 1)
struct ftrfs_rs_event {
	uint64_t re_block_no;
	uint64_t re_timestamp;
	uint32_t re_error_bits;
	uint32_t re_crc32;
}; /* 24 bytes */
#pragma pack(pop)

static volatile int running = 1;
static EVP_PKEY *node_key;
static int lock_fd = -1;

static void handle_sig(int sig)
{
	(void)sig;
	running = 0;
}

/*
 * wait_for_ftrfs_mount -- poll statfs() until /data is a FTRFS filesystem
 * or timeout expires. Returns 0 on success, -1 on timeout.
 *
 * This guarantees that /data/ftrfsd/ is created on FTRFS storage and not
 * on the underlying tmpfs that precedes the FTRFS mount at boot.
 */
static int wait_for_ftrfs_mount(void)
{
	struct statfs sfs;
	int i;

	for (i = 0; i < FTRFSD_MOUNT_TIMEOUT; i++) {
		if (statfs(FTRFSD_KEY_DIR_PARENT, &sfs) == 0 &&
		    (uint32_t)sfs.f_type == FTRFS_MAGIC) {
			syslog(LOG_INFO, "FTRFS mounted on %s (waited %ds)",
			       FTRFSD_KEY_DIR_PARENT, i);
			return 0;
		}
		if (i == 0)
			syslog(LOG_INFO, "waiting for FTRFS mount on %s...",
			       FTRFSD_KEY_DIR_PARENT);
		sleep(1);
	}
	syslog(LOG_ERR, "timeout waiting for FTRFS mount on %s",
	       FTRFSD_KEY_DIR_PARENT);
	return -1;
}

/*
 * acquire_lock -- create and flock() the daemon lockfile.
 * Ensures only one ftrfsd instance runs per node at a time.
 * Returns 0 on success, -1 if another instance holds the lock.
 */
static int acquire_lock(void)
{
	lock_fd = open(FTRFSD_LOCK_FILE, O_CREAT | O_RDWR, 0600);
	if (lock_fd < 0) {
		syslog(LOG_ERR, "open lockfile %s: %s",
		       FTRFSD_LOCK_FILE, strerror(errno));
		return -1;
	}
	if (flock(lock_fd, LOCK_EX | LOCK_NB) < 0) {
		syslog(LOG_ERR, "ftrfsd already running (lockfile %s held)",
		       FTRFSD_LOCK_FILE);
		close(lock_fd);
		lock_fd = -1;
		return -1;
	}
	syslog(LOG_INFO, "acquired lock %s", FTRFSD_LOCK_FILE);
	return 0;
}

static uint32_t crc32_compute(const void *buf, size_t len)
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
		return 0;

	computed = crc32_compute(e, sizeof(*e) - sizeof(e->re_crc32));
	return computed == e->re_crc32;
}

/*
 * base64_encode — encode binary data to base64 string.
 * Returns heap-allocated string, caller must free().
 */
static char *base64_encode(const uint8_t *data, size_t len)
{
	size_t out_len = 4 * ((len + 2) / 3) + 1;
	char *out = malloc(out_len);
	int ret;

	if (!out)
		return NULL;
	ret = EVP_EncodeBlock((uint8_t *)out, data, (int)len);
	if (ret < 0) {
		free(out);
		return NULL;
	}
	return out;
}

/*
 * sign_event — sign the RAF event payload with Ed25519.
 * Payload: block_no || timestamp || error_bits (20 bytes, big-endian).
 * Returns heap-allocated base64 signature string, or NULL on error.
 */
static char *sign_event(const struct ftrfs_rs_event *e)
{
	EVP_MD_CTX *ctx;
	uint8_t payload[20];
	uint8_t sig[64];
	size_t siglen = sizeof(sig);
	char *b64;
	uint64_t be_block, be_ts;
	uint32_t be_err;

	/* big-endian encoding for canonical payload */
	be_block = __builtin_bswap64(e->re_block_no);
	be_ts    = __builtin_bswap64(e->re_timestamp);
	be_err   = __builtin_bswap32(e->re_error_bits);

	memcpy(payload,      &be_block, 8);
	memcpy(payload + 8,  &be_ts,    8);
	memcpy(payload + 16, &be_err,   4);

	ctx = EVP_MD_CTX_new();
	if (!ctx)
		return NULL;

	if (EVP_DigestSignInit(ctx, NULL, NULL, NULL, node_key) != 1 ||
	    EVP_DigestSign(ctx, sig, &siglen, payload, sizeof(payload)) != 1) {
		EVP_MD_CTX_free(ctx);
		return NULL;
	}
	EVP_MD_CTX_free(ctx);

	b64 = base64_encode(sig, siglen);
	return b64;
}

static void log_event(int idx, const struct ftrfs_rs_event *e)
{
	char *sig = sign_event(e);

	if (sig) {
		syslog(LOG_WARNING,
		       "RAF[%02d] block=%llu ts=%llu ns symbols=%u sig=%s",
		       idx,
		       (unsigned long long)e->re_block_no,
		       (unsigned long long)e->re_timestamp,
		       e->re_error_bits,
		       sig);
		free(sig);
	} else {
		syslog(LOG_WARNING,
		       "RAF[%02d] block=%llu ts=%llu ns symbols=%u sig=ERROR",
		       idx,
		       (unsigned long long)e->re_block_no,
		       (unsigned long long)e->re_timestamp,
		       e->re_error_bits);
	}
}

/*
 * load_or_generate_key — load Ed25519 key from disk or generate a new one.
 * Returns EVP_PKEY* or NULL on fatal error.
 */
static EVP_PKEY *load_or_generate_key(void)
{
	EVP_PKEY *pkey = NULL;
	FILE *f;

	/* Try to load existing key */
	f = fopen(FTRFSD_KEY_PRIV, "r");
	if (f) {
		pkey = PEM_read_PrivateKey(f, NULL, NULL, NULL);
		fclose(f);
		if (pkey) {
			syslog(LOG_INFO, "loaded Ed25519 key from %s",
			       FTRFSD_KEY_PRIV);
			return pkey;
		}
		syslog(LOG_WARNING, "failed to parse %s, regenerating",
		       FTRFSD_KEY_PRIV);
	}

	/* Generate new Ed25519 key */
	pkey = EVP_PKEY_Q_keygen(NULL, NULL, "ED25519");
	if (!pkey) {
		syslog(LOG_ERR, "EVP_PKEY_Q_keygen failed");
		return NULL;
	}

	/* Persist private key */
	f = fopen(FTRFSD_KEY_PRIV, "w");
	if (f) {
		chmod(FTRFSD_KEY_PRIV, 0600);
		PEM_write_PrivateKey(f, pkey, NULL, NULL, 0, NULL, NULL);
		fclose(f);
	}

	/* Persist public key */
	f = fopen(FTRFSD_KEY_PUB, "w");
	if (f) {
		PEM_write_PUBKEY(f, pkey);
		fclose(f);
	}

	syslog(LOG_INFO, "generated new Ed25519 node key at %s",
	       FTRFSD_KEY_PRIV);
	return pkey;
}

/*
 * log_pubkey — log the public key in base64 to syslog at startup.
 * This allows any peer to verify our signed RAF events.
 */
static void log_pubkey(EVP_PKEY *pkey)
{
	uint8_t pub[32];
	size_t publen = sizeof(pub);
	char *b64;

	if (EVP_PKEY_get_raw_public_key(pkey, pub, &publen) != 1) {
		syslog(LOG_WARNING, "failed to extract public key");
		return;
	}
	b64 = base64_encode(pub, publen);
	if (b64) {
		syslog(LOG_INFO, "node pubkey (Ed25519): %s", b64);
		free(b64);
	}
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
	syslog(LOG_INFO, "ftrfsd v2 starting on %s (Ed25519 attestation)",
	       dev);

	if (wait_for_ftrfs_mount() < 0) {
		syslog(LOG_ERR, "fatal: FTRFS not mounted, aborting");
		closelog();
		return 1;
	}

	mkdir(FTRFSD_KEY_DIR, 0700);

	if (acquire_lock() < 0) {
		syslog(LOG_ERR, "fatal: cannot acquire lock, aborting");
		closelog();
		return 1;
	}

	node_key = load_or_generate_key();
	if (!node_key) {
		syslog(LOG_ERR, "fatal: cannot initialize node key");
		if (lock_fd >= 0) close(lock_fd);
		closelog();
		return 1;
	}
	log_pubkey(node_key);

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

	EVP_PKEY_free(node_key);
	if (lock_fd >= 0) {
		flock(lock_fd, LOCK_UN);
		close(lock_fd);
	}
	syslog(LOG_INFO, "ftrfsd stopped");
	closelog();
	return 0;
}
