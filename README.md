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
| 2026-04-17 | **FTRFS mounts cleanly on arm64 kernel 7.0 — zero RS errors** |
| 2026-04-17 | RS parity in mkfs verified to match lib/reed_solomon exactly |
| 2026-04-17 | Write/read/umount/rmmod validated on QEMU arm64 |

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
             mission data, application state
             SEU on data → in-place RS correction, event logged

/var/log     FTRFS (read-write)
             system logs, radiation event history
```

dm-verity detects and rejects corruption on read-only volumes.
FTRFS detects and corrects corruption on read-write volumes.

Full rationale:
[Documentation/system-architecture.md](https://github.com/roastercode/FTRFS/blob/main/Documentation/system-architecture.md)

---

## What FTRFS v2 implements (this layer)

The on-disk format v2 introduces a **bitmap block protected by RS FEC**:

```
Block 0      superblock (CRC32 verified)
Block 1-4    inode table
Block 5      bitmap block — RS(255,239) protected   ← NEW in v2
Block 6      root directory data
Block 7+     data blocks
```

The bitmap block stores the free-block allocation state in 16 subblocks
of 239 data bytes each, followed by 16 bytes of Reed-Solomon parity
computed with the same parameters as the kernel's `lib/reed_solomon`:
`init_rs(8, 0x187, fcr=0, prim=1, nroots=16)`.

At mount time, the kernel decodes each subblock. If a SEU has corrupted
the bitmap, the kernel corrects it in place and logs the event to the
Radiation Event Journal — the same mechanism used for data blocks.

**No existing Linux filesystem applies RS FEC to its own allocation
metadata.** FTRFS applies its own medicine to its own structures.

---

## Validated configuration

| Component    | Version                 |
|--------------|-------------------------|
| Yocto        | Styhead 5.1             |
| Kernel       | 7.0.0                   |
| Architecture | arm64 (QEMU cortex-a57) |
| Slurm        | 25.11.4                 |
| Munge        | 0.5.18                  |
| PMIx         | 5.0.3                   |
| FTRFS module | 0.1.0                   |

Slurm cluster test: 3-node job dispatch validated, latency 0.336 s
average, 9-job parallel batch 0.052 s per job.

FTRFS mount test (arm64 QEMU, kernel 7.0):
```
ftrfs: bitmaps initialized (16377 data blocks, 16377 free; 64 inodes, 63 free)
ftrfs: mounted (blocks=16384 free=16377 inodes=64)
```
Zero RS errors. Zero BUG/WARN/Oops.

---

## Quick start

### 1. Clone Yocto and this layer

```sh
git clone https://git.yoctoproject.org/poky -b styhead
cd poky
git clone https://github.com/roastercode/yocto-hardened \
    --branch arm64-ftrfs meta-yocto-hardened-hpc
```

### 2. Set credentials

```sh
cd meta-yocto-hardened-hpc/recipes-core/images
cp credentials.inc.example credentials.inc

# The example hash uses password "root" — suitable for QEMU lab only.
# For production, generate your own:
#   openssl passwd -6 yourpassword
# Each $ must be escaped as \$ in the BitBake file.
```

### 3. Generate cluster secrets

These files are excluded from version control (see `.gitignore`).
They must be created locally before the first build.

```sh
cd meta-yocto-hardened-hpc/recipes-core/images/files

# Munge authentication key — must be identical on all nodes
dd if=/dev/urandom bs=1 count=1024 > munge.key
chmod 400 munge.key

# Admin SSH key
ssh-keygen -t ed25519 -f hpclab_admin -N ""
# hpclab_admin.pub will be installed as authorized_keys for hpcadmin
```

### 4. Configure the cluster

Edit `recipes-core/images/hpc-config.inc`, or override in `local.conf`:

```bitbake
# Point to your generated secrets
HPC_ADMIN_PUBKEY_FILE = "${LAYERDIR}/recipes-core/images/files/hpclab_admin.pub"
HPC_MUNGE_KEY_FILE    = "${LAYERDIR}/recipes-core/images/files/munge.key"

# Adjust network if needed (defaults match the QEMU reference lab)
HPC_MASTER_IP    = "192.168.56.10"
HPC_COMPUTE01_IP = "192.168.56.11"
HPC_COMPUTE02_IP = "192.168.56.12"
HPC_COMPUTE03_IP = "192.168.56.13"
```

### 5. Add the layer and build

```sh
cd poky
source oe-init-build-env build-qemu-arm64

# Add to conf/bblayers.conf:
#   ${TOPDIR}/../meta-yocto-hardened-hpc

bitbake hpc-arm64-master
bitbake hpc-arm64-compute
```

### 6. Boot and set up FTRFS data partition

```sh
# On each node after first boot:
modprobe loop
dd if=/dev/zero of=/tmp/ftrfs.img bs=4096 count=16384
mkfs.ftrfs /tmp/ftrfs.img
losetup /dev/loop0 /tmp/ftrfs.img
mount -t ftrfs /dev/loop0 /data
# Verify: dmesg | grep ftrfs
```

---

## Files excluded from version control

| File | How to generate |
|------|-----------------| 
| `recipes-core/images/credentials.inc` | Copy `.example`, optionally regenerate hash with `openssl passwd -6` |
| `recipes-core/images/files/munge.key` | `dd if=/dev/urandom bs=1 count=1024 > munge.key` |
| `recipes-core/images/files/hpclab_admin.pub` | `ssh-keygen -t ed25519 -f hpclab_admin` |

---

## Known limitations and roadmap

- `yocto-check-layer` conformance: in progress. Some recipes lack
  `LIC_FILES_CHKSUM` and `HOMEPAGE`. Planned before meta-oe submission.
- Tested on arm64 QEMU only. Testing on physical hardware (RPi4,
  industrial SBCs) welcome.
- The GCC 15 and QEMU compatibility patches are environment-specific
  and will be upstreamed or removed before meta-oe submission.
- FTRFS rootfs support (indirect blocks, symlinks, xattr) is not yet
  implemented. FTRFS is currently a data partition filesystem only.
- xfstests Yocto recipe: pending. Required before kernel.org resubmission.

---

## License

MIT — see `LICENSE`.

## Maintainer

Aurelien DESBRIERES `<aurelien@hackers.camp>`
