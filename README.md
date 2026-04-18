# yocto-hardened-hpc

Yocto layer providing a complete hardened embedded Linux stack for HPC
and space applications. Validated on arm64 QEMU, kernel 7.0,
Yocto Styhead 5.1.

## Status

Functional and validated on the reference configuration below.
Not yet submitted to meta-openembedded.

This layer is the Yocto counterpart of the
[FTRFS kernel filesystem](https://github.com/roastercode/FTRFS),
an RFC submitted to linux-fsdevel in April 2026.

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

---

## What this layer provides

- **FTRFS** — Fault-Tolerant Radiation-Robust Filesystem. Out-of-tree
  kernel module with RS FEC, CRC32, Radiation Event Journal, single
  indirect block support (~2 MiB per file).
  See [github.com/roastercode/FTRFS](https://github.com/roastercode/FTRFS)

- **Slurm 25.11.4** — HPC workload manager, cross-compiled for arm64

- **Munge 0.5.18** — authentication service for Slurm

- **PMIx 5.0.3** — process management interface for HPC workloads

- **xfstests image** — `hpc-arm64-xfstests` with GNU grep, GNU hostname,
  xfstests, mkfs.ftrfs -N 256, fsck.ftrfs stub

---

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
# Build
bitbake hpc-arm64-xfstests
CONF=$(ls -t tmp/deploy/images/qemuarm64/hpc-arm64-xfstests-*.qemuboot.conf | head -1)
runqemu qemuarm64 nographic slirp $CONF
```

In QEMU (use large images for generic/001):

```bash
modprobe loop
mkdir -p /data
dd if=/dev/zero of=/data/test.img bs=4096 count=131072 2>/dev/null  # 512 MiB
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
bin/hpc-benchmark.sh
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

## License

MIT — see `LICENSE`.

## Maintainer

Aurelien DESBRIERES `<aurelien@hackers.camp>`
