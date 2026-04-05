# yocto-hardened

Hardened Yocto layer for studies — custom distro and image with progressive security hardening.

## Layer: meta-custom

Custom Yocto layer providing:
- A hardened distro (`poky-hardened`)
- A hardened image (`custom-image`)
- Example recipe (`hello-custom`)
- Custom dm-verity class (`dm-verity-image.bbclass`)

## Branches

| Branch | Description | Trade-off |
|--------|-------------|-----------|
| `main` | Base hardening D1-D7 | Reference branch |
| `squashfs-selinux-permissive` | **Option A** : SquashFS + SELinux permissive | SquashFS has no xattr support → SELinux cannot enforce labels. Suitable for space/embedded where
filesystem immutability (dm-verity) is the primary protection and SELinux is used for audit only |
| `ext4-dm-verity-selinux` | **Option B** : ext4 + dm-verity + SELinux enforcing | Full MAC enforcement. Higher storage overhead, no compression. Suitable for systems requiring strict
process isolation |

## Hardening Status

| Level | Measure | Status |
|-------|---------|--------|
| D1 | Compiler flags (stack protector, FORTIFY, RELRO, PIE) | ✅ Poky default |
| D2 | No debug-tweaks + hashed root password | ✅ Done |
| D3 | Read-only rootfs | ✅ Done |
| D4 | CVE checking (NVD database) | ✅ Done |
| D5 | Custom hardened distro (`poky-hardened`) | ✅ Done |
| D6 | SELinux enforcing (refpolicy-targeted) | ✅ Done (ext4 branch) / ⚠️ Permissive (squashfs branch) |
| D7 | dm-verity + SquashFS kernel support | ✅ Done |
| D8 | dm-verity hash tree generation + overlayfs-etc | ✅ Done |
| D9 | IMA/EVM (runtime file integrity) | 🔲 Todo |
| D10 | Secure Boot | 🔲 Todo |

## Architecture (Option A — squashfs-selinux-permissive)

Boot sequence:
  kernel → mount squashfs (ro) → overlayfs /etc (tmpfs) → userspace

Storage layout:
  /          squashfs (read-only, compressed, dm-verity protected)
  /etc       overlayfs upper = tmpfs (writable, lost on reboot)
  /data      tmpfs (RAM, volatile)
  /var/lib   overlayfs upper = tmpfs (writable, volatile)

## Architecture (Option B — ext4-dm-verity-selinux)

Boot sequence:
  kernel → dm-verity verify ext4 (ro) → SELinux enforcing → userspace

Storage layout:
  /          ext4 (read-only, dm-verity hash verified at boot)
  /etc       overlayfs upper = tmpfs (writable, volatile)

## Usage

### Prerequisites

poky (scarthgap)
meta-openembedded/meta-oe
meta-openembedded/meta-python
meta-selinux

### Setup

```bash
# Add to bblayers.conf
/path/to/meta-custom
/path/to/meta-openembedded/meta-oe
/path/to/meta-openembedded/meta-python
/path/to/meta-selinux

# Set distro in local.conf
DISTRO = "poky-hardened"

# Create credentials (never commit this file)
cp recipes-core/images/credentials.inc.example recipes-core/images/credentials.inc
# Edit credentials.inc with your hashed password
# Generate hash: openssl passwd -6 "yourpassword"

Build

source oe-init-build-env build-qemu-x86
bitbake custom-image

Run in QEMU

runqemu nographic slirp custom-image-qemux86-64.qemuboot.conf

Verify dm-verity root hash

cat tmp/deploy/images/qemux86-64/custom-image-qemux86-64.verity-roothash
