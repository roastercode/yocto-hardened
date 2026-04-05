# yocto-hardened

Hardened Yocto layer for studies — custom distro and image with progressive security hardening.

## Layer: meta-custom

Custom Yocto layer providing:
- A hardened distro (`poky-hardened`)
- A hardened image (`custom-image`)
- Example recipe (`hello-custom`)

## Hardening Status

| Level | Measure | Status |
|-------|---------|--------|
| D1 | Compiler flags (stack protector, FORTIFY, RELRO, PIE) | ✅ Poky default |
| D2 | No debug-tweaks + hashed root password | ✅ Done |
| D3 | Read-only rootfs | ✅ Done |
| D4 | CVE checking (NVD database) | ✅ Done |
| D5 | Custom hardened distro (`poky-hardened`) | ✅ Done |
| D6 | SELinux enforcing (refpolicy-targeted) | ✅ Done |
| D7 | dm-verity kernel support | ✅ Kernel built, bootloader integration pending |
| D8 | dm-verity bootloader integration | 🔲 Todo |
| D9 | IMA/EVM (runtime file integrity) | 🔲 Todo |
| D10 | Secure Boot | 🔲 Todo |

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
