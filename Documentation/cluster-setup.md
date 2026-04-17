# HPC Cluster Setup Guide

This document covers the complete setup procedure for the arm64 HPC cluster,
from build to first successful Slurm job. Follow it exactly to avoid the
common pitfalls that cost hours of debugging.

---

## Prerequisites — files that MUST exist before building

These files are excluded from git (`.gitignore`) and must be created locally
before the first build. The build will succeed without them but the images
will be non-functional.

### 1. SSH admin key

```bash
ssh-keygen -t ed25519 -f ~/.ssh/hpclab_admin -N ""
cp ~/.ssh/hpclab_admin.pub \
    ~/yocto/poky/meta-custom/recipes-core/images/files/hpclab_admin.pub
```

### 2. Munge authentication key

Must be identical on all nodes. Generate once, copy to layer:

```bash
dd if=/dev/urandom bs=1 count=1024 > /tmp/munge.key
chmod 400 /tmp/munge.key
cp /tmp/munge.key \
    ~/yocto/poky/meta-custom/recipes-core/images/files/munge.key
```

### 3. Root password hash

```bash
cp ~/yocto/poky/meta-custom/recipes-core/images/credentials.inc.example \
   ~/yocto/poky/meta-custom/recipes-core/images/credentials.inc
# Default hash = password "root" — lab/QEMU only
# For production: openssl passwd -6 yourpassword
# Each $ must be escaped as \$ in the BitBake file
```

### Verify all files are present

```bash
ls -la ~/yocto/poky/meta-custom/recipes-core/images/files/
# Expected:
#   hpclab_admin.pub   (SSH public key)
#   munge.key          (1024 bytes, mode 400)
ls ~/yocto/poky/meta-custom/recipes-core/images/credentials.inc
```

---

## Build

```bash
cd ~/yocto/poky
source oe-init-build-env build-qemu-arm64
bitbake hpc-arm64-master hpc-arm64-compute
```

## Verify images before deploying

**Always run this after a build, before deploying.**

```bash
IMGFILE=$(ls -t ~/yocto/poky/build-qemu-arm64/tmp/deploy/images/qemuarm64/hpc-arm64-master-qemuarm64-*.ext4 | head -1)
sudo mount -o loop $IMGFILE /mnt/arm64-master

echo "=== hpcadmin shell (must be /bin/sh, NOT /bin/bash) ==="
sudo grep hpcadmin /mnt/arm64-master/etc/passwd

echo "=== authorized_keys (must contain your public key) ==="
sudo cat /mnt/arm64-master/home/hpcadmin/.ssh/authorized_keys

echo "=== munge.key (must exist, 1024 bytes) ==="
sudo ls -la /mnt/arm64-master/etc/munge/munge.key

echo "=== root shadow (must have hash, not * or !) ==="
sudo grep root /mnt/arm64-master/etc/shadow

sudo umount /mnt/arm64-master
```

### Common build failures and fixes

| Symptom | Cause | Fix |
|---------|-------|-----|
| `authorized_keys: No such file` | `hpclab_admin.pub` absent du layer | `cp ~/.ssh/hpclab_admin.pub .../files/` |
| `munge.key: No such file` | `munge.key` absent du layer | Régénérer et copier |
| `root:*:...` dans shadow | `debug-tweaks` absent + pas de credentials.inc | Copier `credentials.inc.example` |
| `hpcadmin:/bin/bash` dans passwd | Ancienne image — rebuild requis | `bitbake hpc-arm64-master hpc-arm64-compute` |

---

## Known constraints

- The shell in the image is BusyBox `/bin/sh` — bash syntax (`for i in $(seq ...)`) does not work
- `/bin/bash` does not exist — hpcadmin must use `/bin/sh` or SSH will refuse the connection
- `read-only-rootfs` is active — `/home`, `/etc` are read-only after boot
- `overlayfs-etc` mounts `/etc` as tmpfs overlay on `/data` at boot
