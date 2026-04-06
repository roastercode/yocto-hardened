# yocto-hardened

Hardened Yocto layer — custom distro and image with progressive security hardening.  
Study project: from minimal image to a fully hardened OS running on real hardware.

## Layer: meta-custom

Custom Yocto layer providing:
- A hardened distro (`poky-hardened`)
- A hardened image (`custom-image`)
- Example recipe (`hello-custom`)

---

## Overall Hardening Status

| Level | Measure | Status |
|-------|---------|--------|
| D1 | Compiler flags (stack protector, FORTIFY, RELRO, PIE) | ✅ Poky default |
| D2 | No debug-tweaks + hashed root password | ✅ Done |
| D3 | Read-only rootfs | ✅ Done |
| D4 | CVE checking (NVD database) | ✅ Done |
| D5 | Custom hardened distro (`poky-hardened`) | ✅ Done |
| D6 | SELinux enforcing — build-time labeling | ✅ Done |
| D7 | dm-verity kernel support | ✅ Done |
| D8 | dm-verity bootloader integration | 🔧 In progress |
| D9 | IMA/EVM (runtime file integrity) | 🔲 Todo |
| D10 | Secure Boot | 🔲 Todo |

---

## Branches

### `ext4-dm-verity-selinux` — Full hardening, BeagleBone Black + external HDD

Target: **BeagleBone Black** booting from SD card, rootfs on **external HDD (USB/SATA)**.

- ext4 + dm-verity + SELinux enforcing
- U-Boot passes root hash at boot
- Full integrity verification at runtime

**Current state:**
- ✅ SELinux enforcing with build-time labeling (`getenforce` → `Enforcing`, 0 `unlabeled_t` files)
- ✅ dm-verity kernel support built
- 🔧 dm-verity bootloader integration (U-Boot root hash passing)
- 🔧 AVC denials at boot to resolve (hwclock, busybox, overlayfs)
- 🔲 Port to BeagleBone Black (MACHINE target + BSP layer)
- 🔲 Validate on real hardware

### `squashfs-selinux-permissive` — Compact image, BeagleBone Black standalone

Target: **BeagleBone Black** standalone, rootfs on **SD card or eMMC**.

- squashfs (native read-only, compressed — suited for constrained flash storage)
- SELinux permissive (first step, enforce once policy is refined)

**Current state:**
- 🔧 Base image boots in QEMU
- 🔲 SELinux policy refinement → switch to enforcing
- 🔲 Port to BeagleBone Black
- 🔲 Validate on real hardware

---

## Key lessons learned (ext4-dm-verity-selinux)

| Problem | Root cause | Fix |
|---------|-----------|-----|
| `selinux_set_labels` override ignored | `inherit selinux-image` appeared **after** the function definition | Move all `inherit` statements **before** function definitions |
| `setfiles` writing `"kernel"` as context | `FC` variable collides with BitBake's Fortran compiler variable | Rename to `SEL_FC`, `SEL_FC_LOCAL`, `SEL_POLICY` |
| `setfiles` validating against host (Gentoo) SELinux policy | Missing `-c policyfile` → host kernel maps unknown types to `"kernel"` SID | Add `-c ${SEL_POLICY}` to validate against target `policy.33` |
| Stale ext4 with wrong xattrs | sstate caching the pre-fix image | `bitbake custom-image -c cleansstate && bitbake custom-image` after any labeling change |

---

## Roadmap

```
Phase 1 — QEMU validation (done)
  ✅ SELinux enforcing, 0 unlabeled files
  ✅ dm-verity kernel support
  ✅ read-only rootfs + overlayfs-etc

Phase 2 — Policy refinement + dm-verity bootloader (in progress)
  🔧 Fix AVC denials at boot (hwclock, busybox, overlayfs)
  🔧 U-Boot integration: pass dm-verity root hash at boot
  🔧 squashfs branch: SELinux permissive → enforcing

Phase 3 — BeagleBone Black port
  🔲 Add meta-ti or meta-arm BSP layer
  🔲 MACHINE = "beaglebone-yocto"
  🔲 Adapt kernel config and bootloader

Phase 4 — Hardware deployment validation
  🔲 squashfs image on BBB SD/eMMC
  🔲 ext4 + dm-verity image on BBB + external HDD
  🔲 Full boot-to-login on real hardware

Phase 5 — Deep-dive tutorial (restart from scratch)
  After hardware validation, restart the full tutorial
  with a step-by-step deep dive into each tool and concept.
```

---

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
