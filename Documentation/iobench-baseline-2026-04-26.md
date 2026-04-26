# FTRFS I/O Benchmark

## Architecture

This baseline is captured on the FTRFS research deployment, which
replaces the earlier loopback-based benchmark setup with a
production-shaped configuration:

- **Rootfs**: read-only squashfs (`hpc-arm64-research-qemuarm64.squashfs`,
  ~52 MB) built from `recipes-core/images/hpc-arm64-research.bb`.
  Replaces the legacy ext4 + dm-verity stack.
- **/etc**: tmpfs overlay (`overlayfs-etc`, upperdir on /run/overlay-etc)
  for runtime configuration writes (hostname, slurm.conf, etc.).
- **/data (FTRFS)**: real partition on `/dev/vdb` (virtio block device,
  64 MB), formatted with `mkfs.ftrfs` at deployment time and mounted
  via `mount -t ftrfs /dev/vdb /data`. **No loopback file**, no
  `losetup`, no `/tmp/ftrfs.img`. The numbers below therefore reflect
  the real virtio-blk + FTRFS data path, not a tmpfs-backed simulation.
- **Hostname**: applied at deployment time via SSH (`hostname <name>`)
  per node, derived from the kernel cmdline `ftrfs.hostname=<name>`
  injected by libvirt.
- **Slurm**: slurmctld on master, slurmd on the three compute nodes;
  munge shared key preseeded in the image at build time.

## Validation status

This run is the first end-to-end validation after the dirent slot
reuse bug fix (FTRFS upstream commit on `main` patching `dir.c`,
`namei.c`, `super.c`; layer files synced lockstep). The fix changes
the directory scan loop to advance by `sizeof(struct ftrfs_dir_entry)`
and treat `d_ino == 0` as "free slot" rather than terminating on
`d_rec_len == 0`. Static invariant `inv5_dirent_no_break_on_zero` is
enforced by `bin/ftrfs-invariants.sh` and was passing at run time.

No ENOENT errors observed during the 100-file create + sync + delete
reproducer that previously produced the bug. M4 (stat bulk on 100
files) completes correctly across all three nodes.

## Run metadata

**Date:** 2026-04-26 22:55:16
**Nodes:** 192.168.56.11 192.168.56.12 192.168.56.13
**Runs per metric:** 10

## Environment

### Node 192.168.56.11

```
HOSTNAME=arm64-compute01
KERNEL=7.0.0
ARCH=aarch64
FTRFS_KO_MD5=02899e992c33435b8aa85440af40a901
FTRFS_BLOCK_DEVICE=/dev/vdb (64 MB virtio-blk, formatted with mkfs.ftrfs)
FTRFS_MOUNT=/dev/vdb /data ftrfs rw,relatime 0 0
```

### Node 192.168.56.12

```
HOSTNAME=arm64-compute02
KERNEL=7.0.0
ARCH=aarch64
FTRFS_KO_MD5=02899e992c33435b8aa85440af40a901
FTRFS_BLOCK_DEVICE=/dev/vdb (64 MB virtio-blk, formatted with mkfs.ftrfs)
FTRFS_MOUNT=/dev/vdb /data ftrfs rw,relatime 0 0
```

### Node 192.168.56.13

```
HOSTNAME=arm64-compute03
KERNEL=7.0.0
ARCH=aarch64
FTRFS_KO_MD5=02899e992c33435b8aa85440af40a901
FTRFS_BLOCK_DEVICE=/dev/vdb (64 MB virtio-blk, formatted with mkfs.ftrfs)
FTRFS_MOUNT=/dev/vdb /data ftrfs rw,relatime 0 0
```

## Results (aggregated across all nodes)

| ID | Metric                       | Min     | Median  | Max     | Stddev  | Unit    |
|----|------------------------------|---------|---------|---------|---------|---------|
| M1 | Write seq + fsync (4MB)      |   4.762 |   5.000 |   5.263 |   0.178 | MB/s    |
| M2 | Read seq cold (4MB)          |  14.286 |  20.000 |  25.000 |   2.207 | MB/s    |
| M4 | Stat bulk (100 files)        |   0.140 |   0.150 |   0.170 |   0.007 | seconds |
| M5 | Small write + fsync (10x64B) |  22.000 |  24.000 |  36.000 |   3.116 | ms/file |

## Methodology

- **M1**: dd if=/dev/zero of=/data/iobench/seq bs=4K count=1024 conv=fsync
  Stresses write path + journal RS event + SB writeback with parity.
- **M2**: drop_caches then dd if=seq of=/dev/null bs=4K
  Stresses readahead path + CRC32 verification.
- **M4**: 100 touch + sync + drop_caches + find | xargs stat
  Stresses inode RS encode/decode path (each inode 256B, iomap + CRC32).
- **M5**: 10 x (dd if=/dev/urandom bs=64 count=1 + sync)
  Worst-case bitmap dirty + SB writeback. Each fsync writes the SB.

## Notes

- M3 (mount cycle) is intentionally omitted in v1: the compute image
  uses overlayfs with /data as upper layer, so unmounting /data would
  break /etc.
- Each measurement is taken after drop_caches for cold-cache discipline.
- Aggregation: 10 runs * 3 nodes = 30 samples per metric.
- ftrfsd peer is active during measurement; fsync triggers RS events to master.
- **FTRFS v3 limit observed**: single-file writes are capped at ~2 MB
  (524 blocks of 4K) on TCG aarch64. M1/M2 use 1 MB to stay safely below.
- **M5 saturation**: 50 successive small writes + sync trigger journal RS
  saturation around iteration 40-45 on TCG. Limited to 10 iterations to keep
  the bench reliable. Re-evaluate with v4 format -- if the limit changes,
  M5 should be reset accordingly.
