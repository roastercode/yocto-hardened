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
| D6 | SELinux enforcing — build-time labeling | ✅ Done |
| D7 | dm-verity kernel support | ✅ Done |
| D8 | dm-verity bootloader integration | 🔲 Todo |
| D9 | IMA/EVM (runtime file integrity) | 🔲 Todo |
| D10 | Secure Boot | 🔲 Todo |

## Branch: ext4-dm-verity-selinux

This branch implements **Option B**: ext4 + dm-verity + SELinux enforcing.

### What works

- SELinux enforcing at boot (`getenforce` → `Enforcing`)
- Build-time SELinux labeling via `setfiles` with `refpolicy-targeted`
  - Override of `selinux_set_labels` to validate contexts against the **target** policy (`-c policy.33`), not the build host policy
  - Workaround for BitBake variable collision: `FC`/`FC_LOCAL` renamed to `SEL_FC`/`SEL_FC_LOCAL` (avoid conflict with the `FC` Fortran compiler BitBake variable)
  - `inherit` ordering fix: `selinux-image` must be inherited **before** the function override in the recipe
  - After any labeling fix: `bitbake custom-image -c cleansstate && bitbake custom-image` required to flush the sstate-cached ext4
- overlayfs-etc: `/etc` writable on tmpfs overlay
- `selinux-init` replaced: no restorecon at first boot (rootfs pre-labeled at build time)

### Known issues / Next steps

- **AVC denials at boot**: hwclock, dmesg, find denied — policy missing rules for several operations. Needs policy refinement or additional `file_contexts.local` entries.
- **overlayfs + SELinux**: `errno: 13` on `/var/volatile/.lib-work/work` — SELinux denies overlayfs setup for the volatile partition.
- **busybox contexts**: `init_exec_t` in `file_contexts.local` may need adjustment (`bin_t` or `shell_exec_t`).
- **dm-verity bootloader integration**: kernel support built, hash tree generated, but root hash not yet passed at boot.

## Usage

### Prerequisites

```
poky (scarthgap)
meta-openembedded/meta-oe
meta-openembedded/meta-python
meta-selinux
```

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
```

### Build

```bash
source oe-init-build-env build-qemu-x86
bitbake custom-image
```

> **Note**: After any change to SELinux labeling logic, run `bitbake custom-image -c cleansstate && bitbake custom-image` to ensure the ext4 is regenerated from a clean state.

### Run in QEMU

```bash
runqemu nographic slirp custom-image-qemux86-64.qemuboot.conf
```
