# yocto-hardened — meta-custom

**Author:** roastercode — Aurelien DESBRIERES `<aurelien@hackers.camp>`

Custom Yocto layer (meta-custom) implementing progressive security hardening
on top of Yocto Styhead (5.1) with `poky-hardened` distro.

Study project: from a minimal hardened image to a fully hardened OS,
then a production-grade HPC cluster with fault-tolerant filesystem.

---

## Repository Branches

| Branch | Description | Target | Status |
|--------|-------------|--------|--------|
| `main` | Base hardening D1-D7, reference branch | QEMU x86-64 | stable |
| `ext4-dm-verity-selinux` | ext4 + dm-verity + SELinux enforcing | BeagleBone Black | stable |
| `squashfs-selinux-permissive` | SquashFS + SELinux permissive + dm-verity | BeagleBone Black | stable |
| `yocto-hpc` | KVM HPC cluster — Slurm 25.11.4 (x86-64) | QEMU/KVM | archived |
| `arm64-ftrfs` | **Active** — arm64 HPC + FTRFS filesystem | QEMU arm64 / KVM | **active** |

### Branch relationships

```
main  ──────────────────────────────────────── base hardening D1-D7
  ├── ext4-dm-verity-selinux ──────────────── dm-verity + SELinux enforcing
  ├── squashfs-selinux-permissive ──────────── squashfs + dm-verity
  ├── yocto-hpc (archived) ─────────────────── HPC x86-64 precursor
  └── arm64-ftrfs (ACTIVE) ─────────────────── arm64 + FTRFS + HPC
```

**`arm64-ftrfs` is the primary development branch.** It contains:
- FTRFS out-of-tree kernel module (RS FEC, CRC32, Radiation Event Journal)
- Slurm 25.11.4 HPC cluster (1 master + 3 compute nodes)
- Full benchmark procedure and reproducible deployment scripts
- All recent hardening fixes and documentation

See [arm64-ftrfs branch](https://github.com/roastercode/yocto-hardened/tree/arm64-ftrfs)
and the [FTRFS kernel filesystem](https://github.com/roastercode/FTRFS).

---

## Hardening Levels (D1–D10)

| Level | Measure | main | ext4-dm-verity | squashfs | yocto-hpc | arm64-ftrfs |
|-------|---------|------|----------------|----------|-----------|-------------|
| D1 | Compiler flags (SSP, FORTIFY, RELRO, PIE) | ✅ | ✅ | ✅ | ✅ | ✅ |
| D2 | No debug-tweaks + hashed root password | ✅ | ✅ | ✅ | ✅ | ✅ |
| D3 | Read-only rootfs + overlayfs-etc | ✅ | ✅ | ✅ | ✅ | ✅ |
| D4 | CVE checking (NVD database) | ✅ | ✅ | ✅ | ✅ | ✅ |
| D5 | Custom hardened distro (poky-hardened) | ✅ | ✅ | ✅ | ✅ | ✅ |
| D6 | SELinux (refpolicy-targeted) | permissive | enforcing | permissive | permissive | permissive |
| D7 | dm-verity kernel support | ✅ | ✅ | ✅ | ✅ | ✅ |
| D8 | dm-verity bootloader integration | 🔧 | 🔧 | ✅ | N/A | 🔧 |
| D9 | FTRFS RS FEC on data partition | ❌ | ❌ | ❌ | ❌ | ✅ |
| D10 | IMA/EVM runtime file integrity | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 |
| D11 | Secure Boot | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 |

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
# Each $ must be escaped as \$ in the BitBake file
```

### Build

```bash
source oe-init-build-env build-qemu-x86
bitbake custom-image
runqemu qemux86-64 nographic
```

---

## License

MIT — see `LICENSE`.

## Maintainer

Aurelien DESBRIERES `<aurelien@hackers.camp>`
