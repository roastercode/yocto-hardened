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

## This Branch — `ext4-dm-verity-selinux`

Full hardening with ext4 + dm-verity + SELinux enforcing.
Target: **BeagleBone Black** booting from SD, rootfs on external HDD.

### Architecture

kernel → dm-verity verify ext4 (ro) → SELinux enforcing → userspace
/          ext4 (read-only, dm-verity hash verified at boot)
/etc       overlayfs upper = tmpfs (writable, volatile)


### Status

- ✅ SELinux enforcing with build-time labeling (getenforce → Enforcing)
- ✅ dm-verity kernel support (CONFIG_DM_VERITY=y)
- ✅ Zero unlabeled_t files at boot
- 🔧 dm-verity U-Boot bootloader integration (root hash passing)
- 🔧 AVC denials at boot to resolve (hwclock, busybox, overlayfs)
- 🔲 BeagleBone Black port (meta-ti BSP layer)
- 🔲 Validate on real hardware

### Key lessons learned

| Problem | Root cause | Fix |
|---------|-----------|-----|
| selinux_set_labels override ignored | inherit after function definition | Move all inherit before functions |
| setfiles writing "kernel" as context | FC collides with BitBake Fortran var | Rename to SEL_FC |
| setfiles validating against host policy | Missing -c policyfile | Add -c to validate against target policy.33 |
| Stale ext4 with wrong xattrs | sstate caching | bitbake -c cleansstate && bitbake |

### Build

```bash
source oe-init-build-env build-qemu-x86
bitbake custom-image -c cleansstate && bitbake custom-image
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
- SELinux enforcing with refpolicy-targeted
- Read-only rootfs verified by dm-verity at boot
