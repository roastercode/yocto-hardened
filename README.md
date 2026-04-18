# yocto-hardened-hpc

Yocto layer providing a complete hardened embedded Linux stack for HPC
and space applications. Validated on arm64 QEMU, kernel 7.0,
Yocto Styhead 5.1.

## Status

Functional and validated on the reference configuration below.
Not yet submitted to meta-openembedded. Testing on other platforms,
bug reports, and contributions are welcome.

This layer is the Yocto counterpart of the
[FTRFS kernel filesystem](https://github.com/roastercode/FTRFS),
an RFC submitted to linux-fsdevel in April 2026.

### Milestone log

| Date | Milestone |
|------|-----------|
| 2026-04-12 | RFC v3 submitted to linux-fsdevel |
| 2026-04-17 | On-disk bitmap block with RS FEC implemented in mkfs and kernel |
| 2026-04-17 | FTRFS mounts cleanly on arm64 kernel 7.0 — zero RS errors |
| 2026-04-17 | RS parity in mkfs verified to match lib/reed_solomon byte-for-byte |
| 2026-04-17 | Write/read/umount/rmmod validated on QEMU arm64 |
| 2026-04-17 | xfstests Yocto recipe added (hpc-arm64-xfstests image) |
| 2026-04-18 | inode bitmap consistency fixed (bitmap_weight at mount) |
| 2026-04-18 | evict_inode: zero i_mode on disk before clear_inode() |
| 2026-04-18 | ftrfs_reconfigure() stub for mount -o remount support |
| 2026-04-18 | migrate_folio added to ftrfs_aops (fixes kernel WARNING) |
| 2026-04-18 | readdir d_off uniqueness fixed (generic/257 PASS) |
| 2026-04-18 | mkfs.ftrfs -N option, default 256 inodes |
| 2026-04-18 | xfstests generic/002, generic/257 PASS — 0 BUG/WARN in dmesg |

---

## What this layer provides

- **FTRFS** — Fault-Tolerant Radiation-Robust Filesystem. Out-of-tree
  kernel module implementing Reed-Solomon FEC, CRC32 per-block checksums,
  and a persistent Radiation Event Journal. Targets MRAM/NOR flash on
  single-device embedded systems where hardware redundancy is unavailable.
  See [github.com/roastercode/FTRFS](https://github.com/roastercode/FTRFS)

- **Slurm 25.11.4** — HPC workload manager, fully cross-compiled for arm64,
  including patches for cross-compilation correctness

- **Munge 0.5.18** — authentication service required by Slurm

- **PMIx 5.0.3** — process management interface for MPI/HPC workloads

- **Reference HPC cluster images** — 1 master/login node + N compute nodes,
  buildable from scratch with a single `bitbake` invocation

- **xfstests image** — dedicated test image (`hpc-arm64-xfstests`) with
  GNU grep, GNU hostname, xfstests, mkfs.ftrfs -N 256, fsck.ftrfs stub

---

## Storage architecture

FTRFS and dm-verity are complementary, not competing. They address
different partition types and different failure modes:

```
/boot        ext4 or squashfs (read-only)
             bootloader, kernel, device tree

/            ext4 + dm-verity (read-only)
             OS binaries verified at boot via Merkle tree
             SEU on rootfs → I/O error, reboot from verified image

/data        FTRFS (read-write)
             SEU on data → in-place RS correction, event logged to
             Radiation Event Journal in superblock

/var/log     FTRFS (read-write)
```

---

## On-disk layout (v2)

```
Block 0        superblock (magic 0x46545246, CRC32 verified)
Block 1..N     inode table (256 bytes/inode, configurable via mkfs -N)
Block N+1      bitmap block (RS FEC protected)
Block N+2      root directory data
Block N+3..    data blocks
```

Default: `mkfs.ftrfs -N 256` → 16 inode table blocks, bitmap at block 17,
data start at block 19.

---

## xfstests results (2026-04-18, arm64 kernel 7.0)

| Test | Result | Notes |
|------|--------|-------|
| generic/002 | ✅ PASS | file create/delete |
| generic/257 | ✅ PASS | directory d_off uniqueness |
| generic/001 | FAIL | writes > 48 KiB — no indirect blocks yet |
| generic/010 | FAIL | dbm requires files > 48 KiB |
| generic/098 | FAIL | pwrite at offset > 48 KiB |

Zero BUG/WARN/Oops/inconsistency in dmesg across all tests.

---

## Quick start

### Prerequisites

- Yocto Styhead (5.1) — `~/yocto/poky`
- meta-openembedded — `~/yocto/meta-openembedded`
- meta-selinux — `~/yocto/meta-selinux`
- Linux kernel 7.0 source — configured in `recipes-kernel/linux/`
- SSH key pair for HPC admin user

### bblayers.conf

```
BBLAYERS ?= " \
  /path/to/poky/meta \
  /path/to/poky/meta-poky \
  /path/to/poky/meta-yocto-bsp \
  /path/to/meta-custom \
  /path/to/meta-openembedded/meta-oe \
  /path/to/meta-openembedded/meta-python \
  /path/to/meta-openembedded/meta-networking \
  /path/to/meta-openembedded/meta-filesystems \
  /path/to/meta-selinux \
"
```

### Build HPC cluster

```bash
source oe-init-build-env build-qemu-arm64
bitbake hpc-arm64-master
bitbake hpc-arm64-compute
```

### Build xfstests image

```bash
bitbake hpc-arm64-xfstests
CONF=$(ls -t tmp/deploy/images/qemuarm64/hpc-arm64-xfstests-*.qemuboot.conf | head -1)
runqemu qemuarm64 nographic slirp $CONF
```

In QEMU:

```bash
modprobe loop
mkdir -p /data
dd if=/dev/zero of=/data/test.img bs=4096 count=16384 2>/dev/null
dd if=/dev/zero of=/data/scratch.img bs=4096 count=16384 2>/dev/null
mkfs.ftrfs -N 256 /data/test.img && mkfs.ftrfs -N 256 /data/scratch.img
losetup /dev/loop0 /data/test.img && losetup /dev/loop1 /data/scratch.img
mkdir -p /mnt/test /mnt/scratch
mount -t ftrfs /dev/loop0 /mnt/test && mount -t ftrfs /dev/loop1 /mnt/scratch
mount -t tmpfs -o size=64M tmpfs /tmp
cd /usr/xfstests && ./check generic/001 generic/002 generic/010 generic/098 generic/257
```

### Run HPC benchmark

```bash
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
