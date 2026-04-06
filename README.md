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
| D8 | dm-verity bootloader integration | 🔧 In progress |
| D9 | IMA/EVM (runtime file integrity) | 🔲 Todo |
| D10 | Secure Boot | 🔲 Todo |

---

## Branch: ext4-dm-verity-selinux

This branch implements **Option B**: ext4 + dm-verity + SELinux enforcing, targeting real hardware deployment (BeagleBone Black + external HDD).

---

## Progress

### D6 — SELinux enforcing ✅

SELinux is fully operational in enforcing mode with build-time labeling:

- `getenforce` returns `Enforcing` at boot
- **0 `unlabeled_t` files** at boot — all files correctly labeled at build time
- No restorecon at first boot (rootfs pre-labeled via `setfiles` with `refpolicy-targeted`)

**Key issues solved during development:**

| Problem | Root cause | Fix |
|---------|-----------|-----|
| `unlabeled_t` on all files | `selinux_set_labels` override not applied | `inherit selinux-image` must come **before** the function override in the recipe |
| `setfiles` writing `"kernel"` context | `FC` variable name collides with BitBake's Fortran compiler variable | Renamed to `SEL_FC`, `SEL_FC_LOCAL`, `SEL_POLICY` |
| `setfiles` validating against host (Gentoo) policy | No `-c policyfile` flag → host kernel maps unknown types to `"kernel"` SID | Added `-c ${SEL_POLICY}` to validate against target `policy.33` |
| Stale ext4 image with wrong xattrs | sstate caching the old image | `bitbake custom-image -c cleansstate && bitbake custom-image` required after any labeling fix |

### D7 — dm-verity kernel support ✅

- Kernel config fragment (`dm-verity.cfg`) enables `CONFIG_DM_VERITY`
- `dm-verity-image.bbclass` generates the hash tree post-image

---

## Current known issues / Next steps

### Boot-time AVC denials (policy refinement needed)

Several processes are denied at boot due to missing policy rules:

- **hwclock**: denied `search` on overlay — needs `var_t` or `tmpfs_t` allow rule
- **dmesg / busybox**: denied `map` on `busybox.nosuid` — busybox context in `file_contexts.local` needs adjustment (`bin_t` or `shell_exec_t` instead of `init_exec_t`)
- **overlayfs**: `errno: 13` on `/var/volatile/.lib-work/work` — SELinux denies overlayfs setup for the volatile partition
- **find**: denied `read`/`getattr` on several paths — shell session context (`local_login_t`) lacks permissions

These do not prevent the system from booting or running, but represent policy gaps to address.

### D8 — dm-verity bootloader integration 🔧

Kernel support is built and the hash tree is generated. The next step is passing the root hash to the bootloader at boot time:
- For BeagleBone Black (U-Boot): pass `dm-mod.create=...` or use a verity-aware initramfs
- Validate read-only enforcement at runtime

### Hardware deployment

The immediate goal is a fully functional image on:
- **BeagleBone Black** (ARM Cortex-A8) — requires a new `MACHINE` target and BSP layer
- **External HDD** — root filesystem on USB/SATA, verity hash stored separately

Once hardware deployment is validated, the tutorial restarts from scratch for a deeper understanding of each step and tool.

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
