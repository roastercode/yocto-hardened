# yocto-hardened — meta-custom

**Author:** roastercode - Aurelien DESBRIERES <aurelien@hackers.camp>

Custom Yocto layer implementing progressive security hardening on Yocto Styhead (5.1).

## Repository Branches

| Branch | Description | Target |
|--------|-------------|--------|
| `main` | Base hardening D1-D7, reference branch | QEMU x86-64 |
| `ext4-dm-verity-selinux` | ext4 + dm-verity + SELinux enforcing | BeagleBone Black |
| `squashfs-selinux-permissive` | SquashFS + SELinux permissive + dm-verity | BeagleBone Black |
| `yocto-hpc` | KVM HPC cluster — Slurm 25.11.4, benchmarked | QEMU/KVM |

## Hardening Matrix

| Level | Measure | main | ext4-dm-verity | squashfs | yocto-hpc |
|-------|---------|------|----------------|----------|-----------|
| D1 | Compiler flags (SSP, FORTIFY, RELRO, PIE) | ✅ | ✅ | ✅ | ✅ |
| D2 | No debug-tweaks + hashed root password | ✅ | ✅ | ✅ | ✅ |
| D3 | Read-only rootfs + overlayfs-etc | ✅ | ✅ | ✅ | ✅ |
| D4 | CVE checking (NVD database) | ✅ | ✅ | ✅ | ✅ |
| D5 | Custom hardened distro (poky-hardened) | ✅ | ✅ | ✅ | ✅ |
| D6 | SELinux refpolicy-targeted | permissive | enforcing | permissive | permissive |
| D7 | dm-verity kernel support | ✅ | ✅ | ✅ | ✅ |
| D8 | dm-verity bootloader integration | 🔧 | 🔧 | ✅ | N/A |
| D9 | IMA/EVM runtime file integrity | 🔲 | 🔲 | 🔲 | 🔲 |
| D10 | Secure Boot | 🔲 | 🔲 | 🔲 | 🔲 |

---

## This Branch — `squashfs-selinux-permissive`

Compact hardened image with SquashFS + SELinux permissive + dm-verity.
Target: **BeagleBone Black** standalone, rootfs on SD card or eMMC.

### Architecture

kernel → mount squashfs (ro, dm-verity) → overlayfs /etc (tmpfs) → userspace
/          SquashFS (read-only, compressed, dm-verity protected)
/etc       overlayfs upper = tmpfs (writable, volatile, lost on reboot)
/data      tmpfs (RAM, volatile)
/var/lib   overlayfs upper = tmpfs (writable, volatile)


### Trade-off vs ext4-dm-verity-selinux

SquashFS has no native xattr support, so SELinux cannot enforce labels on
the rootfs directly. This branch uses SELinux permissive mode for audit only.
dm-verity provides the primary integrity guarantee. For full MAC enforcement,
use the `ext4-dm-verity-selinux` branch instead.

| Criterion | squashfs-selinux-permissive | ext4-dm-verity-selinux |
|-----------|----------------------------|------------------------|
| Filesystem | SquashFS (compressed) | ext4 |
| SELinux | permissive (audit) | enforcing (MAC) |
| Storage | compact, suited for flash | higher overhead |
| dm-verity | ✅ | ✅ |
| xattr support | ❌ (SELinux labels in memory) | ✅ |

### Status

- ✅ Base image boots in QEMU
- ✅ SquashFS + overlayfs-etc functional
- ✅ dm-verity hash generation
- 🔧 SELinux policy refinement → switch to enforcing
- 🔲 BeagleBone Black port (meta-ti BSP layer)
- 🔲 Validate on real hardware

### Build

```bash
source oe-init-build-env build-qemu-x86
bitbake custom-image
```

### Verify dm-verity root hash

```bash
cat tmp/deploy/images/qemux86-64/custom-image-qemux86-64.verity-roothash
```

### Run in QEMU

```bash
runqemu nographic slirp custom-image-qemux86-64.qemuboot.conf
```

---

## Security Notes

- credentials.inc is never versioned
- Private SSH keys kept outside the repo
- SELinux permissive — dm-verity provides primary integrity protection
- Read-only rootfs (SquashFS), writable /etc via overlayfs on tmpfs
