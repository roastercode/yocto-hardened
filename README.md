# yocto-hardened-hpc

Yocto layer providing a complete hardened embedded Linux stack for HPC
and space applications. Validated on arm64 kernel 7.0 (Yocto Styhead 5.1).

## What this layer provides

- **FTRFS** — Fault-Tolerant Radiation-Robust Filesystem (Reed-Solomon FEC,
  CRC32, Radiation Event Journal). Out-of-tree kernel module for Linux 7.0.
  See https://github.com/roastercode/FTRFS
- **Slurm 25.11.4** — HPC workload manager, cross-compiled for arm64
- **Munge 0.5.18** — authentication service for Slurm
- **PMIx 5.0.3** — process management interface for HPC
- **Reference HPC cluster images** — 1 master + N compute nodes, buildable
  from scratch with a single `bitbake` invocation

## Architecture

```
/boot      squashfs or ext4 (read-only)
/          ext4 + dm-verity (read-only, verified at boot)
/data      FTRFS (read-write, RS FEC, Radiation Event Journal)
/var/log   FTRFS (read-write)
```

FTRFS protects read-write data partitions against SEU-induced silent
corruption. dm-verity protects the read-only root filesystem at boot.
See https://github.com/roastercode/FTRFS/blob/main/Documentation/system-architecture.md

## Validated configuration

| Component     | Version       |
|---------------|---------------|
| Yocto         | Styhead (5.1) |
| Kernel        | 7.0.0         |
| Architecture  | arm64 (QEMU cortex-a57) |
| Slurm         | 25.11.4       |
| Munge         | 0.5.18        |
| PMIx          | 5.0.3         |
| FTRFS         | 0.1.0         |

## Quick start

### 1. Clone and set up Yocto

```sh
git clone https://git.yoctoproject.org/poky -b styhead
cd poky
git clone https://github.com/roastercode/yocto-hardened \
    --branch arm64-ftrfs meta-yocto-hardened-hpc
```

### 2. Configure credentials

```sh
cd meta-yocto-hardened-hpc/recipes-core/images
cp credentials.inc.example credentials.inc
# Edit credentials.inc: replace hash with output of: openssl passwd -6 yourpassword
```

### 3. Generate cluster secrets

```sh
# Munge authentication key (shared across all nodes)
dd if=/dev/urandom bs=1 count=1024 > files/munge.key
chmod 400 files/munge.key

# Admin SSH key
ssh-keygen -t ed25519 -f files/hpclab_admin -N ""
# Public key will be at files/hpclab_admin.pub
```

### 4. Configure the cluster

Edit `recipes-core/images/hpc-config.inc` or set in `local.conf`:

```bitbake
HPC_ADMIN_PUBKEY_FILE = "${LAYERDIR}/recipes-core/images/files/hpclab_admin.pub"
HPC_MUNGE_KEY_FILE    = "${LAYERDIR}/recipes-core/images/files/munge.key"
```

Optionally adjust network addresses:

```bitbake
HPC_MASTER_IP    = "192.168.56.10"
HPC_COMPUTE01_IP = "192.168.56.11"
HPC_COMPUTE02_IP = "192.168.56.12"
HPC_COMPUTE03_IP = "192.168.56.13"
```

### 5. Build

```sh
source oe-init-build-env build-qemu-arm64

# Add to bblayers.conf:
#   /path/to/poky/meta-yocto-hardened-hpc

# Build master and compute images
bitbake hpc-arm64-master
bitbake hpc-arm64-compute
```

### 6. Deploy FTRFS partition on each node

```sh
# After boot, on each node:
sudo modprobe ftrfs
sudo mkfs.ftrfs /dev/vdb
sudo mount -t ftrfs /dev/vdb /data
```

## Important: files excluded from version control

The following files contain secrets and are excluded via `.gitignore`.
They must be generated locally before building:

| File | How to generate |
|------|-----------------|
| `recipes-core/images/credentials.inc` | Copy from `.example`, set hash via `openssl passwd -6` |
| `recipes-core/images/files/munge.key` | `dd if=/dev/urandom bs=1 count=1024 > munge.key` |
| `recipes-core/images/files/hpclab_admin.pub` | `ssh-keygen -t ed25519 -f hpclab_admin` |

## License

MIT — see LICENSE file.

## Author

Aurelien DESBRIERES `<aurelien@hackers.camp>`  
RFC submitted to linux-fsdevel, April 2026.
