# beamfs I/O Benchmark

**Date:** 2026-05-10 19:55:26 UTC
**Node:** 192.168.56.10 (beamfs-master)
**Runs per metric:** 10

## Environment

### Node 192.168.56.10

```
HOSTNAME=beamfs-master
KERNEL=7.0.3
ARCH=aarch64
BEAMFS_KO_SHA256=93efeb31dbda4138707fa1a65a889e36de5f39b3abf2bfb6afdc5e961988d6ae
BEAMFS_MOUNT=/dev/vdb on /data type beamfs (rw,relatime)
BEAMFS_FORMAT=v5
BEAMFS_SCHEME=2 (UNIVERSAL_INLINE)
BEAMFS_FEAT_INCOMPAT=0x0000000000000100 (PER_INODE_RS bit 8)
BEAMFS_FEAT_COMPAT=0x0000000000000000
BEAMFS_FEAT_RO_COMPAT=0x0000000000000000
BEAMFS_VOLUME_BLOCKS=262144
BEAMFS_VOLUME_INODES=256
```

## Results (master, single-node)

| ID | Metric                       | Min     | Median  | Max     | Stddev  | Unit    |
|----|------------------------------|---------|---------|---------|---------|---------|
| M1 | Write seq + fsync (1 MiB)    |   2.100 |   2.200 |   2.300 |   0.045 | MB/s    |
| M2 | Read seq cold (1 MiB)        |   5.400 |   5.600 |   6.000 |   0.215 | MB/s    |
| M4 | Stat bulk (100 files)        |   0.184 |   0.190 |   0.199 |   0.004 | seconds |
| M5 | Small write + fsync (10x64B) | 129.341 | 131.034 | 134.997 |   1.401 | ms/file |

## Methodology

- **M1**: `dd if=/dev/zero of=/data/m1.tmp bs=4K count=256 conv=fsync`
  Stresses write path + per-block RS encode (16 sub-blocks of RS(255,239)
  per 4 KiB block) + per-inode RS encode + journal RS event + SB writeback
  with parity.

- **M2**: `drop_caches` then `dd if=/data/m2.tmp of=/dev/null bs=4K`
  Stresses readahead path + per-block RS decode (16 sub-blocks per 4 KiB
  block) + CRC32 verification + folio gather (16 x 239 user bytes per
  block).

- **M4**: 100 touch + sync + drop_caches + find | xargs stat
  Stresses inode RS encode/decode path. With PER_INODE_RS active, each
  inode read triggers CRC32 check and (on mismatch) RS(255,239) decode
  over the 172-byte inode payload.

- **M5**: 10 x (`dd if=/dev/urandom bs=64 count=1` + sync)
  Worst-case bitmap dirty + SB writeback. Each fsync writes the SB with
  full RS encode (13 sub-blocks of 211 data bytes), the bitmap block with
  full RS encode (16 sub-blocks of 239 data bytes), and the per-inode RS
  parity bytes.

## Notes

- M3 (mount cycle) is intentionally omitted: the compute image uses
  overlayfs with `/data` as the device-mount target on `/dev/vdb`, and
  `/data` lifecycle is managed by R19 pipeline (lifecycle.rs +
  cluster_setup.rs), not by the benchmark harness.

- Each measurement is taken after `drop_caches` for cold-cache discipline.

- Aggregation: 10 runs * 1 node (beamfs-master) = 10 samples per metric.
  Cluster-wide aggregation across compute01/02/03 deferred to a future
  benchmark revision (the four nodes share the same kernel and beamfs
  module sha256, results expected to be statistically equivalent).

- **beamfs v5 limit observed**: single-file writes are capped at 524 INLINE
  blocks of 3824 user bytes per block, total 2 003 776 bytes per file
  (the v1 indirect addressing capacity). M1 and M2 use 1 MiB to stay safely
  below this limit. The dindirect and tindirect inode fields are reserved
  on-disk but not yet exercised; activation is queued in the roadmap as a
  future v0.1.x increment without format bump.

- M5 saturation: 50 successive small writes + sync trigger journal RS
  saturation around iteration 40-45 on TCG aarch64 (observation inherited
  from the FTRFS predecessor harness). M5 is limited to 10 iterations to
  keep the bench reliable. The journal saturation behaviour itself is
  expected from the 64-entry circular SB-embedded journal (TM section 6).

## Comparison with FTRFS predecessor (2026-04-28)

| ID | Metric                       | FTRFS v3 median | beamfs v5 median | Delta   |
|----|------------------------------|-----------------|------------------|---------|
| M1 | Write seq + fsync (1 MiB)    |   5.000 MB/s    |   2.200 MB/s     | -56%    |
| M2 | Read seq cold (1 MiB)        |  20.000 MB/s    |   5.600 MB/s     | -72%    |
| M4 | Stat bulk (100 files)        |   0.150 s       |   0.190 s        | +27%    |
| M5 | Small write + fsync (10x64B) |  23.500 ms/file | 131.034 ms/file  | +458%   |

The deltas are consistent with the additional protection beamfs v5
provides relative to FTRFS v3:

- M1 write path: +13 sub-block RS encodes per 4 KiB data block (FTRFS v3
  encoded only metadata, not data blocks).
- M2 read path: +13 sub-block RS decodes per 4 KiB data block, plus a
  16 x 239 user byte gather. The cold-cache penalty falls almost entirely
  on the decode pipeline.
- M4 stat path: +1 RS decode per inode (PER_INODE_RS active in this run;
  FTRFS v3 metadata layout differed).
- M5 small write path: each fsync now drives a full SB RS encode (13 sub-
  blocks of 211 bytes) plus the bitmap RS encode plus the per-inode RS
  parity update; the FTRFS v3 baseline did not have PER_INODE_RS.

These are the expected throughput costs of the universal protection
contract documented in `Documentation/threat-model.md` section 6.1
(no opt-in path, no flag-gated bypass) and `Documentation/data-protection-
design.md` section 4 (decision in favour of `s_data_protection_scheme=2`
UNIVERSAL_INLINE for the v5.0 RFC baseline). Read-path overhead is
expected to remain in this range "except on correction events"; see
`Documentation/roadmap.md` Stage 4 exit condition 5.

## Reproducibility

Tarball: `/tmp/beamfs-throughput-20260510-195526Z.tar.gz`
sha256: `8ed074db10c34221e2dea12aa868eab8c376b7d29c0443dbaaab7c0b3a6e96dd`

Contents:

- `env-master.txt` (master node environment fingerprint)
- `m1-write-seq.txt` (10 raw MB/s samples)
- `m2-read-seq.txt` (10 raw MB/s samples)
- `m4-stat-bulk.txt` (10 raw seconds samples)
- `m5-small-write.txt` (10 raw ms/file samples)

Driver: ad-hoc shell loop (this benchmark run was not yet integrated into
`beamfs-bench` as a sub-command). Future revision: add a
`beamfs-bench throughput` sub-command that produces the same metric
ladder with manifest GPG signing and aggregation across the 4 cluster
nodes.

