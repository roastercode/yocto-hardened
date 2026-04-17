# FTRFS Integration Guide

This document covers FTRFS integration in the HPC cluster images —
how it is built, deployed, and validated.

---

## What FTRFS provides in this layer

FTRFS is deployed as an out-of-tree kernel module (`ftrfs-module`) and
a userspace formatting tool (`mkfs-ftrfs`). It provides a read-write
data partition with Reed-Solomon FEC protection on all data blocks and
on the block allocation bitmap.

### On-disk layout (v2)

```
Block 0      superblock (CRC32 verified, covers s_bitmap_blk)
Block 1-4    inode table
Block 5      bitmap block — RS(255,239) FEC protected
Block 6      root directory data
Block 7+     data blocks
```

### RS FEC parameters

Both the kernel module and `mkfs.ftrfs` use identical parameters:

```c
init_rs(8, 0x187, fcr=0, prim=1, nroots=16)
// GF(2^8), primitive polynomial 0x187
// 16 parity bytes per 239-byte subblock
// Corrects up to 8 symbol errors per subblock
```

---

## Build

FTRFS is built automatically as part of the master and compute images.
To rebuild the module only:

```bash
bitbake ftrfs-module -c cleanall && bitbake ftrfs-module
bitbake mkfs-ftrfs -c cleanall && bitbake mkfs-ftrfs
```

The compiled `.ko` is at:
```
tmp/work/qemuarm64-poky-linux/ftrfs-module/0.1.0/sysroot-destdir/lib/modules/7.0.0/updates/ftrfs.ko
```

---

## Deployment

The benchmark script injects `ftrfs.ko` directly into each image before
booting, via loop mount. This is required because the module is not yet
included in the kernel build (`EXTRA_OECONF` / in-tree integration is
a future step).

```bash
FTRFS_KO=$(find ~/yocto/poky/build-qemu-arm64/tmp/work/qemuarm64-poky-linux/ftrfs-module/ \
    -name "ftrfs.ko" | tail -1)

sudo mount -o loop /var/lib/libvirt/images/hpc-arm64/arm64-master.ext4 /mnt/arm64-master
sudo mkdir -p /mnt/arm64-master/lib/modules/7.0.0/updates
sudo cp $FTRFS_KO /mnt/arm64-master/lib/modules/7.0.0/updates/ftrfs.ko
sudo umount /mnt/arm64-master
```

---

## Validation on each node

After boot, run on each node:

```bash
sudo insmod /lib/modules/7.0.0/updates/ftrfs.ko
sudo dd if=/dev/zero of=/tmp/ftrfs.img bs=4096 count=16384 2>/dev/null
sudo mkfs.ftrfs /tmp/ftrfs.img
sudo modprobe loop
sudo losetup /dev/loop0 /tmp/ftrfs.img
sudo mount -t ftrfs /dev/loop0 /data
dmesg | grep ftrfs
```

Expected output (zero RS errors):
```
ftrfs: module loaded (FTRFS Fault-Tolerant Radiation-Robust FS)
ftrfs: bitmaps initialized (16377 data blocks, 16377 free; 64 inodes, 63 free)
ftrfs: mounted (blocks=16384 free=16377 inodes=64)
```

Any `uncorrectable` message indicates a mismatch between mkfs parity
and the kernel RS parameters — rebuild `mkfs-ftrfs`.

---

## FTRFS write from Slurm job

```bash
SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ~/.ssh/hpclab_admin"
$SSH hpcadmin@192.168.56.10 "
srun --nodes=3 --ntasks=3 sh -c 'echo \$(hostname):\$(date) | sudo tee /data/slurm-\$(hostname).txt'
srun --nodes=3 --ntasks=3 cat /data/slurm-\$(hostname).txt
"
```

---

## Validated configuration

| Component | Version | Date |
|-----------|---------|------|
| FTRFS module | 0.1.0 | 2026-04-17 |
| Kernel | 7.0.0 | 2026-04-17 |
| Architecture | arm64 QEMU cortex-a57 | |
| RS FEC | RS(255,239), 16 parity bytes | |
| Bitmap block | Block 5, RS FEC protected | |
| Mount result | Zero RS errors | ✅ |
| Slurm write | Functional on 3 compute nodes | ✅ |
