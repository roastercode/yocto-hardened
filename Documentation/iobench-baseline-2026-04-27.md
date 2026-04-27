# FTRFS I/O Benchmark

**Date:** 2026-04-27 11:52:22
**Nodes:** 192.168.56.11 192.168.56.12 192.168.56.13
**Runs per metric:** 10

## Environment

### Node 192.168.56.11

```
HOSTNAME=arm64-compute01
KERNEL=7.0.1
ARCH=aarch64
FTRFS_KO_MD5=5d07d48b5fdb8cd22a66e008240785f9
FTRFS_IMG_SIZE=0
FTRFS_MOUNT=/dev/vdb /data ftrfs rw,relatime 0 0
```

### Node 192.168.56.12

```
HOSTNAME=arm64-compute02
KERNEL=7.0.1
ARCH=aarch64
FTRFS_KO_MD5=5d07d48b5fdb8cd22a66e008240785f9
FTRFS_IMG_SIZE=0
FTRFS_MOUNT=/dev/vdb /data ftrfs rw,relatime 0 0
```

### Node 192.168.56.13

```
HOSTNAME=arm64-compute03
KERNEL=7.0.1
ARCH=aarch64
FTRFS_KO_MD5=5d07d48b5fdb8cd22a66e008240785f9
FTRFS_IMG_SIZE=0
FTRFS_MOUNT=/dev/vdb /data ftrfs rw,relatime 0 0
```

## Results (aggregated across all nodes)

| ID | Metric                       | Min     | Median  | Max     | Stddev  | Unit    |
|----|------------------------------|---------|---------|---------|---------|---------|
| M1 | Write seq + fsync (4MB)      |   2.128 |   5.000 |   5.556 |   0.584 | MB/s    |
| M2 | Read seq cold (4MB)          |  12.500 |  20.000 |  25.000 |   2.458 | MB/s    |
| M4 | Stat bulk (100 files)        |   0.140 |   0.150 |   0.160 |   0.006 | seconds |
| M5 | Small write + fsync (10x64B) |  21.000 |  23.000 |  30.000 |   2.331 | ms/file |

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
