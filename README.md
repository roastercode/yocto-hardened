# yocto-hardened — FTRFS HPC cluster + trust substrate

Yocto BSP layer for radiation-hardened embedded Linux on arm64.
Counterpart of the [FTRFS kernel filesystem](https://github.com/roastercode/FTRFS),
an RFC submitted to linux-fsdevel in April 2026.

## What this is

FTRFS (Fault-Tolerant Radiation-Robust Filesystem) is a new Linux filesystem
designed for environments where storage is permanently exposed to radiation:
nanosatellites, CubeSats, nuclear robotics, space HPC. The current
implementation provides CRC32 integrity on metadata (superblock, inodes,
Radiation Event Journal) and RS(255,239) Reed-Solomon FEC on the on-disk
allocation bitmap via the kernel's `lib/reed_solomon` library. Extending
RS FEC to data blocks at writeback is on the roadmap. The codebase targets
under 5000 auditable lines for DO-178C and ECSS-E-ST-40C certification.

This layer validates FTRFS on a real arm64 HPC cluster (Slurm 25.11.4, 4 nodes,
QEMU KVM) and builds the infrastructure above the filesystem: event attestation,
per-node RAF monitoring, and the foundations of a distributed trust substrate
for autonomous systems that cannot rely on continuous connectivity or a central
authority.

## Branches

| Branch | Description | Status |
|--------|-------------|--------|
| `arm64-ftrfs` | FTRFS + Slurm HPC cluster, ftrfsd v3, xfstests validation | ✅ validated |
| `yocto-hpc` | x86-64 HPC cluster (Styhead 5.1, Slurm) | ✅ stable |
| `ext4-dm-verity-selinux` | dm-verity + SELinux hardened image | stable |
| `squashfs-selinux-permissive` | squashfs + SELinux permissive | stable |

## Status

Functional and validated on the reference configuration below.
Not yet submitted to meta-openembedded.

FTRFS RFC v3 submitted to linux-fsdevel, April 2026.
Active reviewers: Matthew Wilcox, Darrick J. Wong, Andreas Dilger,
Pedro Falcato (SUSE), Gao Xiang. Covered by Phoronix.

### Milestone log

| Date | Milestone |
|------|-----------|
| 2026-04-12 | RFC v3 submitted to linux-fsdevel |
| 2026-04-17 | On-disk bitmap block with RS FEC implemented and validated |
| 2026-04-17 | FTRFS mounts cleanly on arm64 kernel 7.0 — zero RS errors |
| 2026-04-17 | xfstests Yocto recipe added (hpc-arm64-xfstests image) |
| 2026-04-18 | inode bitmap consistency fixed (bitmap_weight at mount) |
| 2026-04-18 | evict_inode: zero i_mode on disk before clear_inode() |
| 2026-04-18 | ftrfs_reconfigure() stub for mount -o remount support |
| 2026-04-18 | migrate_folio added to ftrfs_aops (fixes kernel WARNING) |
| 2026-04-18 | readdir d_off uniqueness fixed (generic/257 PASS) |
| 2026-04-18 | mkfs.ftrfs -N option, default 256 inodes |
| 2026-04-18 | Single indirect block support (~2 MiB per file) |
| 2026-04-18 | Data block free on delete (ftrfs_free_data_blocks) |
| 2026-04-18 | xfstests generic/002, 010, 098, 257 PASS — 0 BUG/WARN |
| 2026-04-20 | edac.c: migrate RS FEC to lib/reed_solomon (Eric Biggers review) |
| 2026-04-21 | ftrfsd: RAF monitor daemon, deployed on 4-node arm64 cluster |
| 2026-04-21 | trust substrate prototype initiated (later merged into arm64-ftrfs) |
| 2026-04-21 | Slurm benchmark: 0.26s job latency, 9-job throughput 5.41s, 0 BUG/WARN |
| 2026-04-21 | ftrfsd v2: Ed25519 per-node attestation, statfs FTRFS wait, flock lockfile |
| 2026-04-21 | 4 unique Ed25519 keys verified on master + 3 compute nodes |
| 2026-04-25 | FTRFS upstream sync: ftrfs_write_inode_raw cross-TU, REED_SOLOMON_ENC8/DEC8 select, drop unimplemented XATTR/SECURITY Kconfig |
| 2026-04-25 | Kernel config cleanup: KASAN/UBSAN removed (out-of-tree module mismatch with non-instrumented kernel) |
| 2026-04-25 | ftrfsd v3: distributed attestation over TCP with Ed25519, master/peer modes, inject_raf helper |
| 2026-04-25 | 4-node HPC cluster bench re-validated, ftrfsd master+3 peers operational, 0 RS errors, 0 BUG/WARN |

---

## What this layer provides

- **FTRFS kernel module** — RS(255,239) FEC, CRC32, Radiation Event Journal,
  indirect blocks (~2 MiB/file), iomap IO path.
  See [github.com/roastercode/FTRFS](https://github.com/roastercode/FTRFS)

- **ftrfsd v3** — Radiation Event Journal monitor daemon with Ed25519
  per-node attestation and cluster-wide signed event propagation over TCP.
  Three modes: standalone (local syslog), `--master` (TCP listener on
  port 7700), `--peer <master_ip>` (connects to master, signs and forwards
  events). Binary protocol with HELLO/ACK/EVENT/PING messages; Ed25519
  provides authentication (no TLS). Per-node Ed25519 keypair stored on
  FTRFS at `/data/ftrfsd/`. Deployed on all 4 cluster nodes with unique
  keys. Companion tool `inject_raf` injects valid RAF events into the
  superblock for end-to-end test of the signature/propagation chain.
  Second brick of the trust substrate for autonomous distributed systems.

- **Slurm 25.11.4** — HPC workload manager, cross-compiled for arm64

- **Munge 0.5.18** — authentication service for Slurm

- **PMIx 5.0.3** — process management interface for HPC workloads

- **xfstests image** — `hpc-arm64-xfstests` with GNU grep, GNU hostname,
  xfstests, mkfs.ftrfs -N 256, fsck.ftrfs stub

---

## Benchmark results (2026-04-21, arm64 kernel 7.0, 4-node cluster)

| Test | Result |
|------|--------|
| Job submission latency (single node) | 0.26s |
| 3-node parallel job | 0.35s |
| 9-job throughput | 5.41s |
| FTRFS mount (all 4 nodes) | ✅ clean |
| ftrfsd RAF monitor (all 4 nodes) | ✅ running |
| dmesg BUG/WARN/Oops | 0 |

Re-validated 2026-04-25 — same configuration, same FTRFS sources after
upstream sync, ftrfsd v3 master+3 peers operational on the 4 nodes.
Functional behavior consistent with the reference run; zero RS errors,
zero BUG/WARN/Oops in dmesg.

## xfstests results (2026-04-18, arm64 kernel 7.0)

| Test | Result | Notes |
|------|--------|-------|
| generic/002 | ✅ PASS | file create/delete |
| generic/010 | ✅ PASS | dbm — indirect blocks |
| generic/098 | ✅ PASS | pwrite at offset > 48 KiB |
| generic/257 | ✅ PASS | directory d_off uniqueness |
| generic/001 | env limit | needs >2 GiB test image (not a FTRFS bug) |

Zero BUG/WARN/Oops/inconsistency in dmesg across all tests.

### Running xfstests

```bash
source oe-init-build-env build-qemu-arm64
bitbake hpc-arm64-xfstests
CONF=$(ls -t tmp/deploy/images/qemuarm64/hpc-arm64-xfstests-*.qemuboot.conf | head -1)
runqemu qemuarm64 nographic slirp $CONF
```

In QEMU:

```bash
modprobe loop
mkdir -p /data
dd if=/dev/zero of=/data/test.img bs=4096 count=131072 2>/dev/null
dd if=/dev/zero of=/data/scratch.img bs=4096 count=131072 2>/dev/null
mkfs.ftrfs -N 256 /data/test.img && mkfs.ftrfs -N 256 /data/scratch.img
losetup /dev/loop0 /data/test.img && losetup /dev/loop1 /data/scratch.img
mkdir -p /mnt/test /mnt/scratch
mount -t ftrfs /dev/loop0 /mnt/test && mount -t ftrfs /dev/loop1 /mnt/scratch
mount -t tmpfs -o size=64M tmpfs /tmp
mount -t tmpfs -o size=64M tmpfs /usr/xfstests/results
cd /usr/xfstests && ./check generic/002 generic/010 generic/098 generic/257
```

---

## Quick start — HPC cluster

```bash
source oe-init-build-env build-qemu-arm64
bitbake hpc-arm64-master
bitbake hpc-arm64-compute
bash bin/hpc-benchmark.sh
```

---

## Reference configuration

| Component | Version |
|-----------|---------|
| Yocto | Styhead 5.1 |
| Linux kernel | 7.0.0 |
| Architecture | arm64 (cortex-a57) |
| QEMU | 9.0.2 |
| Slurm | 25.11.4 |
| Munge | 0.5.18 |
| PMIx | 5.0.3 |
| GCC | 14.2.0 (cross) |

---

## Press & community coverage

- Phoronix — *FTRFS: New Fault-Tolerant File-System Proposed For Linux* (2026-04-13):
  https://www.phoronix.com/news/FTRFS-Linux-File-System
- Phoronix — *Linux 7.1 Staging* (FTRFS mention):
  https://www.phoronix.com/news/Linux-7.1-Staging
- LWN.net — *ftrfs: Fault-Tolerant Radiation-Robust Filesystem*:
  https://lwn.net/Articles/1067452/
- daily.dev:
  https://app.daily.dev/posts/ftrfs-new-fault-tolerant-file-system-proposed-for-linux-m5rbha19y
- Reddit r/filesystems:
  https://www.reddit.com/r/filesystems/comments/1skjj18/
- Reddit r/phoronix_com:
  https://www.reddit.com/r/phoronix_com/comments/1skbg7q/
- X/Twitter @phoronix:
  https://x.com/phoronix/status/2043678672775754091
- X/Twitter @jreuben1:
  https://x.com/jreuben1/status/2043912800376889429
- Telegram Linuxgram (2026-04-13):
  https://t.me/s/linuxgram?before=18454
- YouTube — Genai Linux News:
  https://www.youtube.com/watch?v=EKA93IBcCvk

RFC threads on lore.kernel.org:

| Version | Date | Lore archive |
|---------|------|--------------|
| RFC v1 | 2026-04-13 | https://lore.kernel.org/linux-fsdevel/20260413142357.515792-1-aurelien@hackers.camp/ |
| RFC v2 | 2026-04-13 | https://lore.kernel.org/linux-fsdevel/20260413230601.525400-1-aurelien@hackers.camp/ |
| RFC v3 | 2026-04-14 | https://lore.kernel.org/linux-fsdevel/20260414120726.5713-1-aurelien@hackers.camp/ |

## License

MIT — see `LICENSE`.

## Maintainer

Aurelien DESBRIERES `<aurelien@hackers.camp>`

---

*Part of the FTRFS ecosystem:*
*[github.com/roastercode/FTRFS](https://github.com/roastercode/FTRFS)*
