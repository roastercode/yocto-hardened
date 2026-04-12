# meta-custom — Yocto HPC Layer

Custom Yocto layer for a mini-lab HPC cluster based on KVM/QEMU, Slurm, MPI and NFS.

## Architecture

(Gentoo host, i7-12700F, 32GB RAM)

├── hpc-master      (192.168.56.10) — slurmctld, nfs-server

├── hpc-compute01   (192.168.56.11) — slurmd

├── hpc-compute02   (192.168.56.12) — slurmd

├── hpc-compute03   (192.168.56.13) — slurmd

└── hpc-storage     (192.168.56.20) — nfs-server, scratch


## Component Versions

| Component | Version |
|-----------|---------|
| Yocto     | Scarthgap (5.0 styhead) |
| Slurm     | 25.11.4 |
| Munge     | 0.5.15 |
| PMIx      | 5.0.3 |
| MPICH     | (meta-oe) |
| libevent  | 2.1.12 |

## Branches

| Branch | Description |
|--------|-------------|
| `main` | System hardening D1-D7 (SELinux, dm-verity) |
| `yocto-hpc` | KVM HPC cluster — **active branch** |

## Host Requirements

| Tool | Version |
|------|---------|
| GCC  | 15.2.1 |
| Python | 3.11.15 |
| glibc | 2.42 |
| Git  | 2.52.0 |
| ninja | 1.13+ |

> **Note:** This layer includes fixes for GCC 15 + glibc 2.42 + ninja 1.13 incompatibilities
> that affect Yocto Scarthgap builds on a modern Gentoo host.

## Build

```bash
cd ~/yocto/poky
source oe-init-build-env build-qemu-x86
bitbake hpc-image-master hpc-image-compute hpc-image-storage
```

## Images

| Image | Size | Contents |
|-------|------|----------|
| hpc-image-master | ~500 MB | slurmctld, munge, nfs-server, mpich |
| hpc-image-compute | ~300 MB | slurmd, munge, nfs-client, mpich, hwloc |
| hpc-image-storage | ~206 MB | nfs-server, e2fsprogs |

## VM Deployment

```bash
DEPLOY=tmp/deploy/images/qemux86-64
sudo qemu-img convert -f raw -O qcow2 \
  ${DEPLOY}/hpc-image-master-qemux86-64.ext4 \
  /var/lib/libvirt/images/hpclab/master.qcow2
```

## SSH Access

```bash
ssh -i ~/.ssh/hpclab_admin hpcadmin@192.168.56.10  # master
ssh -i ~/.ssh/hpclab_admin hpcadmin@192.168.56.11  # compute01
```

---

## GCC 15 / glibc 2.42 / ninja 1.13 Compatibility Fixes

Building Yocto Scarthgap on a Gentoo host with GCC 15, glibc 2.42 and ninja 1.13
requires a series of patches and bbappend fixes. All fixes are in meta-custom.

### qemu-native / qemu-system-native

| Fix | File |
|-----|------|
| ninja 1.13 rejects float -l parameter from MAKEFLAGS | recipes-devtools/qemu/qemu-native_%.bbappend |
| struct sched_attr redefinition with glibc 2.42 | recipes-devtools/qemu/qemu-native_%.bbappend + patch 0001-qemu-fix-sched-attr-glibc-2.42.patch |
| ninja -l float on qemu-system-native (separate recipe) | recipes-devtools/qemu/qemu-system-native_%.bbappend |

### elfutils-native

| Fix | File |
|-----|------|
| GCC 15 -Werror=unterminated-string-initialization (C only) | recipes-devtools/elfutils/elfutils_%.bbappend |

### bash

| Fix | File |
|-----|------|
| GCC 15 C23 implicit function declarations in mkbuiltins | recipes-extended/bash/bash_%.bbappend |

### llvm-native 18.1.8

LLVM 18 was written assuming uint64_t and friends are transitively available via
system headers. GCC 15 enforces stricter header inclusion, breaking the build in
multiple files. Fixed by two complementary approaches:

| Fix | File |
|-----|------|
| SmallVector.h missing #include cstdint | patch 0001-llvm-fix-smallvector-cstdint-gcc15.patch |
| All other uint*_t undeclared in C++ TUs (X86, AMDGPU targets, etc.) | CXXFLAGS:append:class-native = " -include cstdint" in recipes-devtools/llvm/llvm_%.bbappend |

The -include cstdint flag is intentionally restricted to CXXFLAGS only.
Applying it to CFLAGS or assembler files (.S) injects C++ typedefs into assembly
preprocessing, causing fatal assembler errors (tested and confirmed).

---

## Slurm 25.11.4 Cross-Compilation Patches

Slurm 25.11.4 requires 5 patches to build and function correctly under Yocto cross-compilation:

| Patch | Issue fixed |
|-------|-------------|
| 0001 | -Wl,--allow-shlib-undefined on hdf5 and pmix plugins |
| 0002 | DEFAULT_PREP_PLUGINS="" — prep/script uses an internal slurmd symbol unavailable at link time |
| 0003 | -Wl,--export-dynamic on slurmctld to expose its symbols to plugins |
| 0004 | RTLD_LAZY|RTLD_GLOBAL in plugin.c for cross-plugin symbol resolution |
| 0005 | Stubs for internal slurmctld symbols in libslurmfull for client tools |

Upstream fork with patches: https://github.com/roastercode/slurm/tree/fix/cross-compile-plugin-symbols

### Slurm QA fixes

- WORKDIR to UNPACKDIR for file:// sources (Yocto styhead behaviour change)
- INSANE_SKIP buildpaths on all Slurm packages (DWARF debug info contains build paths,
  unavoidable in cross-compilation)

---

## PMIx 5.0.3

| Fix | Description |
|-----|-------------|
| buildpaths QA | pmix_info binary, pmixcc-wrapper-data.txt, pmix_config.h, pmix.pc contain TMPDIR references. Text files cleaned via sed in do_install:append; binary covered by INSANE_SKIP. |

---

## Cluster Status

- [x] Munge — inter-node authentication
- [x] slurmctld — Slurm controller on master
- [x] slurmd — compute daemon on 3 nodes
- [x] sinfo — nodes idle
- [x] sbatch — jobs running on compute01-03
- [ ] cgroup v1 at boot (manual mount required)
- [ ] NFS /scratch
- [ ] Multi-node MPI tests

## TODO

1. Integrate cgroup v1 mount into hpc-image-compute (fstab or init script)
2. Configure NFS /scratch from hpc-storage
3. Multi-node MPI tests with mpich
4. SchedMD bug report: https://support.schedmd.com/

## Security Notes

- credentials.inc is never versioned
- Private SSH keys kept outside the repo
- SELinux permissive (overlayfs + tmpfs incompatible with enforcing)
- hpcadmin with ed25519 key, sudo NOPASSWD, root SSH disabled
