// SPDX-License-Identifier: GPL-2.0-only
/*
 * ftrfsd — FTRFS Radiation Event Journal daemon v3
 *
 * Reads the RAF (Radiation Event Journal) from a FTRFS superblock,
 * signs each correction event with a node-local Ed25519 key, and
 * propagates signed events to a master node for cluster-wide attestation.
 *
 * This implements the second brick of the semantic-sync trust substrate:
 * verifiable distributed event propagation without a central authority.
 *
 * Modes:
 *   ftrfsd <device>                    -- standalone (local syslog only)
 *   ftrfsd <device> --master           -- master mode (listen on TCP 7700)
 *   ftrfsd <device> --peer <master_ip> -- peer mode (connect to master)
 *
 * Protocol (binary, no TLS -- Ed25519 provides authentication):
 *   HELLO  [0x01][32 bytes pubkey][64 bytes hostname\0-padded]
 *   ACK    [0x01=ok | 0x00=rejected]
 *   EVENT  [0x03][24 bytes ftrfs_rs_event][64 bytes Ed25519 signature]
 *   PING   [0x04]
 *
 * Key management:
 *   Private key: /data/ftrfsd/node.key (PEM, 0600)
 *   Public key:  /data/ftrfsd/node.pub (PEM)
 *   Peers dir:   /data/ftrfsd/peers/   (master only)
 *
 * Signed payload per event (20 bytes, big-endian):
 *   re_block_no (8) || re_timestamp (8) || re_error_bits (4)
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
#include <sys/stat.h>
#include <sys/vfs.h>
#include <sys/file.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <netinet/in.h>
#include <arpa/inet.h>

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
#define FTRFSD_KEY_DIR        "/data/ftrfsd"
#define FTRFSD_KEY_PRIV       "/data/ftrfsd/node.key"
#define FTRFSD_KEY_PUB        "/data/ftrfsd/node.pub"
#define FTRFSD_LOCK_FILE      "/data/ftrfsd/ftrfsd.lock"
#define FTRFSD_PEERS_DIR      "/data/ftrfsd/peers"
#define FTRFSD_MOUNT_TIMEOUT  30
#define FTRFSD_PEER_PORT      7700
#define FTRFSD_MAX_PEERS      16
#define FTRFSD_PING_INTERVAL  30
#define FTRFSD_HOSTNAME_LEN   64

/* Protocol message types */
#define MSG_HELLO 0x01
#define MSG_ACK   0x02
#define MSG_EVENT 0x03
#define MSG_PING  0x04

#pragma pack(push, 1)
struct ftrfs_rs_event {
	uint64_t re_block_no;
	uint64_t re_timestamp;
	uint32_t re_error_bits;
	uint32_t re_crc32;
}; /* 24 bytes */

struct msg_hello {
	uint8_t type;                          /* MSG_HELLO */
	uint8_t pubkey[32];                    /* Ed25519 raw public key */
	char    hostname[FTRFSD_HOSTNAME_LEN]; /* null-padded */
}; /* 97 bytes */

struct msg_event {
	uint8_t               type;    /* MSG_EVENT */
	struct ftrfs_rs_event event;   /* 24 bytes */
	uint8_t               sig[64]; /* Ed25519 signature */
}; /* 89 bytes */
#pragma pack(pop)

/* Peer state (master side) */
struct peer {
	int     fd;
	uint8_t pubkey[32];
	char    hostname[FTRFSD_HOSTNAME_LEN];
	int     active;
};

/* sig_atomic_t: modified by signal handler, guarantees atomic read/write */
static sig_atomic_t running = 1;
static EVP_PKEY    *node_key;
static int          lock_fd = -1;

static void handle_sig(int sig)
{
	(void)sig;
	running = 0;
}

/*
 * wait_for_ftrfs_mount -- poll statfs() until /data is FTRFS or timeout.
 * Prevents creating keys on the underlying tmpfs before FTRFS mounts.
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
			syslog(LOG_INFO,
			       "waiting for FTRFS mount on %s...",
			       FTRFSD_KEY_DIR_PARENT);
		sleep(1);
	}
	syslog(LOG_ERR, "timeout waiting for FTRFS mount on %s",
	       FTRFSD_KEY_DIR_PARENT);
	return -1;
}

/*
 * acquire_lock -- flock() exclusive lock, one instance per node.
 * Required for DO-178C auditability: single controller per RAF.
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
		syslog(LOG_ERR,
		       "ftrfsd already running (lockfile %s held)",
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
 * build_payload -- canonical 20-byte big-endian payload for signing.
 * Canonical encoding ensures cross-node signature verification.
 */
static void build_payload(const struct ftrfs_rs_event *e, uint8_t *out)
{
	uint64_t be_block = __builtin_bswap64(e->re_block_no);
	uint64_t be_ts    = __builtin_bswap64(e->re_timestamp);
	uint32_t be_err   = __builtin_bswap32(e->re_error_bits);

	memcpy(out,      &be_block, 8);
	memcpy(out + 8,  &be_ts,    8);
	memcpy(out + 16, &be_err,   4);
}

/*
 * sign_payload -- sign 20-byte payload with node key, write 64-byte sig.
 * Returns 0 on success, -1 on error.
 */
static int sign_payload(const uint8_t *payload, uint8_t *sig)
{
	EVP_MD_CTX *ctx;
	size_t siglen = 64;

	ctx = EVP_MD_CTX_new();
	if (!ctx)
		return -1;
	if (EVP_DigestSignInit(ctx, NULL, NULL, NULL, node_key) != 1 ||
	    EVP_DigestSign(ctx, sig, &siglen, payload, 20) != 1) {
		EVP_MD_CTX_free(ctx);
		return -1;
	}
	EVP_MD_CTX_free(ctx);
	return 0;
}

/*
 * verify_payload -- verify 20-byte payload against sig and raw pubkey.
 * Returns 1 if valid, 0 if invalid, -1 on error.
 */
static int verify_payload(const uint8_t *payload, const uint8_t *sig,
			   const uint8_t *pubkey_raw)
{
	EVP_PKEY   *pkey;
	EVP_MD_CTX *ctx;
	int ret;

	pkey = EVP_PKEY_new_raw_public_key(EVP_PKEY_ED25519, NULL,
					   pubkey_raw, 32);
	if (!pkey)
		return -1;
	ctx = EVP_MD_CTX_new();
	if (!ctx) {
		EVP_PKEY_free(pkey);
		return -1;
	}
	if (EVP_DigestVerifyInit(ctx, NULL, NULL, NULL, pkey) != 1) {
		EVP_MD_CTX_free(ctx);
		EVP_PKEY_free(pkey);
		return -1;
	}
	ret = EVP_DigestVerify(ctx, sig, 64, payload, 20);
	EVP_MD_CTX_free(ctx);
	EVP_PKEY_free(pkey);
	return ret;
}

static void log_event_local(int idx, const struct ftrfs_rs_event *e)
{
	uint8_t payload[20];
	uint8_t sig[64];
	char   *b64;

	build_payload(e, payload);
	if (sign_payload(payload, sig) < 0) {
		syslog(LOG_WARNING,
		       "RAF[%02d] block=%llu ts=%llu ns symbols=%u sig=ERROR",
		       idx,
		       (unsigned long long)e->re_block_no,
		       (unsigned long long)e->re_timestamp,
		       e->re_error_bits);
		return;
	}
	b64 = base64_encode(sig, 64);
	syslog(LOG_WARNING,
	       "RAF[%02d] block=%llu ts=%llu ns symbols=%u sig=%s",
	       idx,
	       (unsigned long long)e->re_block_no,
	       (unsigned long long)e->re_timestamp,
	       e->re_error_bits,
	       b64 ? b64 : "ERROR");
	free(b64);
}

static EVP_PKEY *load_or_generate_key(void)
{
	EVP_PKEY *pkey = NULL;
	FILE     *f;

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

	pkey = EVP_PKEY_Q_keygen(NULL, NULL, "ED25519");
	if (!pkey) {
		syslog(LOG_ERR, "EVP_PKEY_Q_keygen failed");
		return NULL;
	}

	f = fopen(FTRFSD_KEY_PRIV, "w");
	if (f) {
		chmod(FTRFSD_KEY_PRIV, 0600);
		PEM_write_PrivateKey(f, pkey, NULL, NULL, 0, NULL, NULL);
		fclose(f);
	}
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
 * get_raw_pubkey -- extract 32-byte raw Ed25519 public key.
 * Returns 0 on success, -1 on error.
 */
static int get_raw_pubkey(EVP_PKEY *pkey, uint8_t *out)
{
	size_t len = 32;

	return (EVP_PKEY_get_raw_public_key(pkey, out, &len) == 1) ? 0 : -1;
}

static void log_pubkey(EVP_PKEY *pkey)
{
	uint8_t pub[32];
	char   *b64;

	if (get_raw_pubkey(pkey, pub) < 0) {
		syslog(LOG_WARNING, "failed to extract public key");
		return;
	}
	b64 = base64_encode(pub, 32);
	if (b64) {
		syslog(LOG_INFO, "node pubkey (Ed25519): %s", b64);
		free(b64);
	}
}

/*
 * scan_raf -- read superblock, fill events[], return RAF head index.
 * Returns head on success, -1 on error.
 */
static int scan_raf(const char *dev,
		    struct ftrfs_rs_event *events, int *nev)
{
	uint8_t               sb[FTRFS_SB_SIZE];
	struct ftrfs_rs_event journal[FTRFS_RS_JOURNAL_SIZE];
	uint32_t magic;
	int fd, i;

	*nev = 0;
	fd = open(dev, O_RDONLY);
	if (fd < 0)
		return -1;
	if (read(fd, sb, FTRFS_SB_SIZE) != FTRFS_SB_SIZE) {
		close(fd);
		return -1;
	}
	close(fd);

	memcpy(&magic, sb, 4);
	if (magic != FTRFS_MAGIC)
		return -1;

	memcpy(journal, sb + FTRFS_RS_JOURNAL_OFF, sizeof(journal));
	for (i = 0; i < FTRFS_RS_JOURNAL_SIZE; i++) {
		if (entry_is_valid(&journal[i]))
			events[(*nev)++] = journal[i];
	}
	return (int)(uint8_t)sb[FTRFS_RS_HEAD_OFF];
}

/*
 * run_standalone -- local syslog only, no network.
 */
static void run_standalone(const char *dev)
{
	struct ftrfs_rs_event events[FTRFS_RS_JOURNAL_SIZE];
	int nev, head, i;

	while (running) {
		head = scan_raf(dev, events, &nev);
		if (head < 0) {
			syslog(LOG_ERR, "RAF scan failed on %s", dev);
		} else {
			for (i = 0; i < nev; i++)
				log_event_local(i, &events[i]);
			syslog(LOG_DEBUG, "RAF scan done, head=%d", head);
		}
		sleep(FTRFS_POLL_INTERVAL);
	}
}

/*
 * run_master -- listen on TCP 7700, receive and verify events from peers.
 * Each peer authenticates with its Ed25519 public key via HELLO.
 * All received events are verified before logging.
 */
static void run_master(const char *dev)
{
	struct peer           peers[FTRFSD_MAX_PEERS];
	struct ftrfs_rs_event events[FTRFS_RS_JOURNAL_SIZE];
	int srv_fd, nev, head, i, opt;
	int npeers = 0;
	struct sockaddr_in addr;
	fd_set rfds;
	struct timeval tv;
	int maxfd;

	memset(peers, 0, sizeof(peers));

	srv_fd = socket(AF_INET, SOCK_STREAM, 0);
	if (srv_fd < 0) {
		syslog(LOG_ERR, "socket: %s", strerror(errno));
		return;
	}
	opt = 1;
	setsockopt(srv_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

	memset(&addr, 0, sizeof(addr));
	addr.sin_family      = AF_INET;
	addr.sin_addr.s_addr = INADDR_ANY;
	addr.sin_port        = htons(FTRFSD_PEER_PORT);

	if (bind(srv_fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
		syslog(LOG_ERR, "bind port %d: %s",
		       FTRFSD_PEER_PORT, strerror(errno));
		close(srv_fd);
		return;
	}
	if (listen(srv_fd, FTRFSD_MAX_PEERS) < 0) {
		syslog(LOG_ERR, "listen: %s", strerror(errno));
		close(srv_fd);
		return;
	}
	syslog(LOG_INFO, "master listening on port %d", FTRFSD_PEER_PORT);

	while (running) {
		FD_ZERO(&rfds);
		FD_SET(srv_fd, &rfds);
		maxfd = srv_fd;

		for (i = 0; i < npeers; i++) {
			if (!peers[i].active)
				continue;
			FD_SET(peers[i].fd, &rfds);
			if (peers[i].fd > maxfd)
				maxfd = peers[i].fd;
		}

		tv.tv_sec  = FTRFS_POLL_INTERVAL;
		tv.tv_usec = 0;

		if (select(maxfd + 1, &rfds, NULL, NULL, &tv) < 0) {
			if (errno == EINTR)
				continue;
			break;
		}

		/* Accept new peer */
		if (FD_ISSET(srv_fd, &rfds) &&
		    npeers < FTRFSD_MAX_PEERS) {
			struct sockaddr_in peer_addr;
			socklen_t addrlen = sizeof(peer_addr);
			int pfd = accept(srv_fd,
					 (struct sockaddr *)&peer_addr,
					 &addrlen);
			if (pfd >= 0) {
				struct msg_hello hello;
				uint8_t ack;
				ssize_t n;

				n = recv(pfd, &hello, sizeof(hello),
					 MSG_WAITALL);
				if (n == (ssize_t)sizeof(hello) &&
				    hello.type == MSG_HELLO) {
					hello.hostname[FTRFSD_HOSTNAME_LEN - 1]
						= '\0';
					peers[npeers].fd     = pfd;
					peers[npeers].active = 1;
					memcpy(peers[npeers].pubkey,
					       hello.pubkey, 32);
					memcpy(peers[npeers].hostname,
					       hello.hostname,
					       FTRFSD_HOSTNAME_LEN);
					char *b64 = base64_encode(
						hello.pubkey, 32);
					syslog(LOG_INFO,
					       "peer connected: %s pubkey=%s",
					       peers[npeers].hostname,
					       b64 ? b64 : "?");
					free(b64);
					ack = 0x01;
					npeers++;
				} else {
					ack = 0x00;
					syslog(LOG_WARNING,
					       "rejected peer: bad HELLO");
				}
				send(pfd, &ack, 1, 0);
				if (ack == 0x00)
					close(pfd);
			}
		}

		/* Receive messages from peers */
		for (i = 0; i < npeers; i++) {
			uint8_t type;
			ssize_t n;

			if (!peers[i].active ||
			    !FD_ISSET(peers[i].fd, &rfds))
				continue;

			n = recv(peers[i].fd, &type, 1, MSG_WAITALL);
			if (n != 1) {
				syslog(LOG_INFO, "peer %s disconnected",
				       peers[i].hostname);
				close(peers[i].fd);
				peers[i].active = 0;
				continue;
			}

			if (type == MSG_PING)
				continue;

			if (type == MSG_EVENT) {
				struct msg_event ev;
				uint8_t payload[20];
				int ok;

				ev.type = type;
				n = recv(peers[i].fd,
					 ((uint8_t *)&ev) + 1,
					 sizeof(ev) - 1, MSG_WAITALL);
				if (n != (ssize_t)(sizeof(ev) - 1))
					continue;

				build_payload(&ev.event, payload);
				ok = verify_payload(payload, ev.sig,
						    peers[i].pubkey);
				if (ok == 1) {
					char *b64 = base64_encode(ev.sig, 64);

					syslog(LOG_WARNING,
					       "PEER %s RAF block=%llu ts=%llu ns symbols=%u sig=%s VERIFIED",
					       peers[i].hostname,
					       (unsigned long long)
					       ev.event.re_block_no,
					       (unsigned long long)
					       ev.event.re_timestamp,
					       ev.event.re_error_bits,
					       b64 ? b64 : "?");
					free(b64);
				} else {
					syslog(LOG_ERR,
					       "PEER %s RAF SIGNATURE INVALID",
					       peers[i].hostname);
				}
			}
		}

		/* Local RAF scan */
		head = scan_raf(dev, events, &nev);
		if (head >= 0) {
			for (i = 0; i < nev; i++)
				log_event_local(i, &events[i]);
			syslog(LOG_DEBUG,
			       "RAF scan done, head=%d peers=%d",
			       head, npeers);
		}
	}

	for (i = 0; i < npeers; i++)
		if (peers[i].active)
			close(peers[i].fd);
	close(srv_fd);
}

/*
 * run_peer -- connect to master, propagate local RAF events with signature.
 * Reconnects automatically on disconnect. Sends PING every 30s if idle.
 */
static void run_peer(const char *dev, const char *master_ip)
{
	struct ftrfs_rs_event events[FTRFS_RS_JOURNAL_SIZE];
	int    sock_fd   = -1;
	int    nev, head, i;
	int    connected = 0;
	time_t last_ping = 0;
	char   hostname[FTRFSD_HOSTNAME_LEN];

	gethostname(hostname, sizeof(hostname) - 1);
	hostname[FTRFSD_HOSTNAME_LEN - 1] = '\0';

	while (running) {
		if (!connected) {
			struct sockaddr_in addr;
			struct msg_hello hello;
			uint8_t ack;

			if (sock_fd >= 0) {
				close(sock_fd);
				sock_fd = -1;
			}

			sock_fd = socket(AF_INET, SOCK_STREAM, 0);
			if (sock_fd < 0) {
				sleep(FTRFS_POLL_INTERVAL);
				continue;
			}

			memset(&addr, 0, sizeof(addr));
			addr.sin_family = AF_INET;
			addr.sin_port   = htons(FTRFSD_PEER_PORT);
			if (inet_pton(AF_INET, master_ip,
				      &addr.sin_addr) != 1) {
				syslog(LOG_ERR, "invalid master IP: %s",
				       master_ip);
				close(sock_fd);
				sock_fd = -1;
				sleep(FTRFS_POLL_INTERVAL);
				continue;
			}

			if (connect(sock_fd, (struct sockaddr *)&addr,
				    sizeof(addr)) < 0) {
				syslog(LOG_ERR,
				       "connect to master %s:%d: %s",
				       master_ip, FTRFSD_PEER_PORT,
				       strerror(errno));
				close(sock_fd);
				sock_fd = -1;
				sleep(FTRFS_POLL_INTERVAL);
				continue;
			}

			memset(&hello, 0, sizeof(hello));
			hello.type = MSG_HELLO;
			get_raw_pubkey(node_key, hello.pubkey);
			memcpy(hello.hostname, hostname,
			       FTRFSD_HOSTNAME_LEN);
			send(sock_fd, &hello, sizeof(hello), 0);

			if (recv(sock_fd, &ack, 1, MSG_WAITALL) != 1 ||
			    ack != 0x01) {
				syslog(LOG_ERR, "master rejected HELLO");
				close(sock_fd);
				sock_fd = -1;
				sleep(FTRFS_POLL_INTERVAL);
				continue;
			}

			syslog(LOG_INFO, "connected to master %s:%d",
			       master_ip, FTRFSD_PEER_PORT);
			connected = 1;
			last_ping = time(NULL);
		}

		/* Scan local RAF and forward events */
		head = scan_raf(dev, events, &nev);
		if (head < 0) {
			syslog(LOG_ERR, "RAF scan failed on %s", dev);
		} else {
			for (i = 0; i < nev; i++) {
				struct msg_event ev;
				uint8_t payload[20];

				log_event_local(i, &events[i]);
				ev.type  = MSG_EVENT;
				ev.event = events[i];
				build_payload(&events[i], payload);
				if (sign_payload(payload, ev.sig) < 0)
					continue;
				if (send(sock_fd, &ev,
					 sizeof(ev), 0) < 0) {
					syslog(LOG_ERR,
					       "send event failed: %s",
					       strerror(errno));
					connected = 0;
					break;
				}
			}
			syslog(LOG_DEBUG, "RAF scan done, head=%d", head);
		}

		/* PING if idle */
		if (connected &&
		    (time(NULL) - last_ping) >= FTRFSD_PING_INTERVAL) {
			uint8_t ping = MSG_PING;

			if (send(sock_fd, &ping, 1, 0) < 0)
				connected = 0;
			else
				last_ping = time(NULL);
		}

		sleep(FTRFS_POLL_INTERVAL);
	}

	if (sock_fd >= 0)
		close(sock_fd);
}

int main(int argc, char *argv[])
{
	const char *dev;
	const char *master_ip = NULL;
	int         mode_master = 0;

	if (argc < 2) {
		fprintf(stderr, "Usage: ftrfsd <device> [--master | --peer <ip>]\n");
		return 1;
	}
	dev = argv[1];

	if (argc >= 3) {
		if (strcmp(argv[2], "--master") == 0) {
			mode_master = 1;
		} else if (argc >= 4 &&
			   strcmp(argv[2], "--peer") == 0) {
			master_ip = argv[3];
		}
	}

	signal(SIGTERM, handle_sig);
	signal(SIGINT,  handle_sig);
	signal(SIGPIPE, SIG_IGN);

	openlog("ftrfsd", LOG_PID | LOG_NDELAY, LOG_DAEMON);
	syslog(LOG_INFO,
	       "ftrfsd v3 starting on %s (Ed25519%s%s)",
	       dev,
	       mode_master ? ", master"    : "",
	       master_ip   ? ", peer mode" : "");

	if (wait_for_ftrfs_mount() < 0) {
		syslog(LOG_ERR, "fatal: FTRFS not mounted, aborting");
		closelog();
		return 1;
	}

	mkdir(FTRFSD_KEY_DIR, 0700);
	if (mode_master)
		mkdir(FTRFSD_PEERS_DIR, 0700);

	if (acquire_lock() < 0) {
		syslog(LOG_ERR, "fatal: cannot acquire lock, aborting");
		closelog();
		return 1;
	}

	node_key = load_or_generate_key();
	if (!node_key) {
		syslog(LOG_ERR, "fatal: cannot initialize node key");
		if (lock_fd >= 0)
			close(lock_fd);
		closelog();
		return 1;
	}
	log_pubkey(node_key);

	if (mode_master)
		run_master(dev);
	else if (master_ip)
		run_peer(dev, master_ip);
	else
		run_standalone(dev);

	EVP_PKEY_free(node_key);
	if (lock_fd >= 0) {
		flock(lock_fd, LOCK_UN);
		close(lock_fd);
	}
	syslog(LOG_INFO, "ftrfsd stopped");
	closelog();
	return 0;
}
