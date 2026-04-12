# meta-custom — Yocto HPC Layer

Custom Yocto layer for a mini-lab HPC cluster based on KVM/QEMU, Slurm, MPI and NFS.
Built on Yocto Styhead (5.1) with full system hardening (read-only rootfs, overlayfs-etc,
SELinux permissive, dm-verity support).

---

## Benchmark Results — April 12, 2026

Cluster: 1 master + 3 compute nodes (KVM/QEMU on Gentoo, i7-12700F)

| Test | Result |
|------|--------|
| Job submission latency (single node) | 2.016s |
| 3-node parallel job (N=3, ntasks=3) | 2.008s |
| 9-job throughput submission | 0.021s |
| Job distribution | 3 jobs/node (perfect balance) |
| Nodes at test time | compute[01-03] idle → running |

All 14 test jobs completed successfully across compute01, compute02, compute03.

---

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
| Yocto     | Styhead (5.1) |
| Slurm     | 25.11.4 |
| Munge     | 0.5.18 |
| PMIx      | 5.0.3 |
| OpenSSH   | 10.3p1 |
| MPICH     | (meta-oe) |
| libevent  | 2.1.12 |
| Linux kernel | 7.0-rc7 mainline |

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
> that affect Yocto Styhead builds on a modern Gentoo host.

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
sudo virsh destroy hpc-master hpc-compute01 hpc-compute02 hpc-compute03 2>/dev/null
sleep 3
sudo qemu-img convert -f raw -O qcow2 \
  ${DEPLOY}/hpc-image-master-qemux86-64.ext4 \
  /var/lib/libvirt/images/hpclab/master.qcow2
sudo qemu-img convert -f raw -O qcow2 \
  ${DEPLOY}/hpc-image-compute-qemux86-64.ext4 \
  /var/lib/libvirt/images/hpclab/compute-base.qcow2
for n in 01 02 03; do
  sudo qemu-img create -f qcow2 \
    -b /var/lib/libvirt/images/hpclab/compute-base.qcow2 \
    -F qcow2 \
    /var/lib/libvirt/images/hpclab/compute${n}.qcow2
done
sudo virsh start hpc-master hpc-compute01 hpc-compute02 hpc-compute03
```

## SSH Access

```bash
ssh -i ~/.ssh/hpclab_admin hpcadmin@192.168.56.10  # master
ssh -i ~/.ssh/hpclab_admin hpcadmin@192.168.56.11  # compute01
```

---

## GCC 15 / glibc 2.42 / ninja 1.13 Compatibility Fixes

| Recipe | Fix | File |
|--------|-----|------|
| qemu-native | ninja 1.13 float -l + sched_attr glibc 2.42 | recipes-devtools/qemu/qemu-native_%.bbappend |
| qemu-system-native | ninja 1.13 float -l | recipes-devtools/qemu/qemu-system-native_%.bbappend |
| elfutils-native | GCC 15 -Werror=unterminated-string-initialization | recipes-devtools/elfutils/elfutils_%.bbappend |
| bash | GCC 15 C23 implicit function declarations | recipes-extended/bash/bash_%.bbappend |
| llvm-native 18.1.8 | uint*_t undeclared (missing cstdint) | patch + CXXFLAGS -include cstdint |
| openssh 10.3p1 | sshd-session/sshd-auth binaries missing | recipes-connectivity/openssh/openssh_10.3p1.bb |

---

## Slurm 25.11.4 Cross-Compilation Patches

| Patch | Issue fixed |
|-------|-------------|
| 0001 | -Wl,--allow-shlib-undefined on all plugins |
| 0002 | DEFAULT_PREP_PLUGINS="" — prep/script undefined symbol |
| 0003 | -Wl,--export-dynamic on slurmctld |
| 0004 | RTLD_LAZY|RTLD_GLOBAL in plugin.c |
| 0005 | Stubs for internal slurmctld symbols in libslurmfull |

Upstream fork: https://github.com/roastercode/slurm/tree/fix/cross-compile-plugin-symbols

## Slurm Runtime Configuration

- SlurmctldHost=master (Slurm 25.11.4 directive, replaces ControlMachine)
- ProctrackType=proctrack/linuxproc (no cgroup on KVM)
- CgroupPlugin=disabled (no /sys/fs/cgroup on this kernel config)
- munge.key owned by root:root, 0400 (munge 0.5.18 requirement)

---

## Cluster Status

- [x] SSH access (OpenSSH 10.3p1, ed25519 key)
- [x] Munge 0.5.18 — inter-node authentication
- [x] slurmctld — Slurm controller on master
- [x] slurmd — compute daemon on 3 nodes
- [x] sinfo — nodes idle
- [x] sbatch — jobs running on compute01-03
- [x] Benchmark — 14 jobs, perfect 3-way load balance
- [ ] cgroup v1 at boot (manual mount required)
- [ ] NFS /scratch
- [ ] Multi-node MPI tests

## TODO

1. Integrate cgroup v1 mount into hpc-image-compute
2. Configure NFS /scratch from hpc-storage
3. Multi-node MPI tests with mpich
4. Auto-start munge/slurm at boot via init.d

## Security Notes

- credentials.inc is never versioned
- Private SSH keys kept outside the repo
- SELinux permissive (overlayfs-etc incompatible with enforcing)
- Read-only rootfs with overlayfs-etc on tmpfs
- dm-verity kernel support enabled (CONFIG_DM_VERITY=y)
- hpcadmin with ed25519 key, sudo NOPASSWD, root SSH disabled
- munge.key: 1024 bytes random, root:root 0400
