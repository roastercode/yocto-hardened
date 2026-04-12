# yocto-hardened — meta-custom

**Author:** roastercode - Aurelien DESBRIERES <aurelien@hackers.camp>

Custom Yocto layer (meta-custom) implementing progressive security hardening
on top of Yocto Styhead (5.1) with `poky-hardened` distro.

Study project: from a minimal hardened image to a fully hardened OS,
then a production-grade HPC cluster.

---

## Repository Branches

| Branch | Description | Target |
|--------|-------------|--------|
| `main` | Base hardening D1-D7, reference branch | QEMU x86-64 |
| `ext4-dm-verity-selinux` | ext4 + dm-verity + SELinux enforcing | BeagleBone Black |
| `squashfs-selinux-permissive` | SquashFS + SELinux permissive + dm-verity | BeagleBone Black |
| `yocto-hpc` | KVM HPC cluster — Slurm 25.11.4, benchmarked | QEMU/KVM |

---

## Hardening Levels (D1–D10)

| Level | Measure | main | ext4-dm-verity | squashfs | yocto-hpc |
|-------|---------|------|----------------|----------|-----------|
| D1 | Compiler flags (SSP, FORTIFY, RELRO, PIE) | ✅ | ✅ | ✅ | ✅ |
| D2 | No debug-tweaks + hashed root password | ✅ | ✅ | ✅ | ✅ |
| D3 | Read-only rootfs + overlayfs-etc | ✅ | ✅ | ✅ | ✅ |
| D4 | CVE checking (NVD database) | ✅ | ✅ | ✅ | ✅ |
| D5 | Custom hardened distro (poky-hardened) | ✅ | ✅ | ✅ | ✅ |
| D6 | SELinux (refpolicy-targeted) | permissive | enforcing | permissive | permissive |
| D7 | dm-verity kernel support | ✅ | ✅ | ✅ | ✅ |
| D8 | dm-verity bootloader integration | 🔧 | 🔧 | ✅ | N/A |
| D9 | IMA/EVM runtime file integrity | 🔲 | 🔲 | 🔲 | 🔲 |
| D10 | Secure Boot | 🔲 | 🔲 | 🔲 | 🔲 |

---

## This Branch — `main`

Base hardening reference point. Minimal hardened image for QEMU x86-64.

### Layer contents

- `poky-hardened` distro (CVE checking, SELinux, no x11, no debug-tweaks)
- `custom-image` hardened image (read-only rootfs, overlayfs-etc)
- `hello-custom` example recipe
- `dm-verity-image.bbclass` — dm-verity support class

### Host Requirements

| Tool | Version |
|------|---------|
| GCC | 15.2.1 |
| Python | 3.11.15 |
| glibc | 2.42 |
| Git | 2.52.0 |

### Setup

```bash
# bblayers.conf
/path/to/meta-custom
/path/to/meta-openembedded/meta-oe
/path/to/meta-openembedded/meta-python
/path/to/meta-selinux

# local.conf
DISTRO = "poky-hardened"

# Credentials (never commit)
cp recipes-core/images/credentials.inc.example \
   recipes-core/images/credentials.inc
# Generate hash: openssl passwd -6 "yourpassword"
```

### Build

```bash
source oe-init-build-env build-qemu-x86
bitbake custom-image
```

### Run in QEMU

```bash
runqemu nographic slirp custom-image-qemux86-64.qemuboot.conf
```

---

## Security Notes

- `credentials.inc` is never versioned
- Private SSH keys kept outside the repo
- SELinux permissive on main (enforcing in ext4-dm-verity-selinux branch)
- Read-only rootfs with overlayfs-etc on tmpfs

---

## Roadmap

- D8: dm-verity bootloader integration (U-Boot root hash passing)
- D9: IMA/EVM runtime file integrity
- D10: Secure Boot
- BeagleBone Black port (ext4-dm-verity-selinux and squashfs branches)
- HPC cluster production deployment (see yocto-hpc branch)
