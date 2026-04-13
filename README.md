# meta-custom — Yocto arm64 FTRFS HPC Layer

Custom Yocto layer for an arm64 HPC cluster with FTRFS as data partition,
based on KVM/QEMU, Slurm 25.11.4, and the FTRFS fault-tolerant filesystem.
Built on Yocto Styhead (5.1) targeting qemuarm64 (cortex-a57, Linux 7.0-rc7).

---

## Benchmark Results — April 13, 2026

Cluster: 1 master + 3 compute nodes (KVM/QEMU on Gentoo, i7-12700F)
FTRFS partition: 64 MiB per node (/dev/vdb, mounted at /var/tmp/ftrfs)

| Test | Result |
|------|--------|
| Job submission latency (single node) | 0.079s |
| 3-node parallel job (N=3, ntasks=3) | 0.392s |
| 9-job throughput submission | 0.481s |
| Job distribution | perfect balance |
| Nodes at test time | compute[01-03] idle → running |
| FTRFS mount | ✅ all nodes |
| ftrfs.ko (arm64, Linux 7.0-rc7) | ✅ |

All 9 test jobs completed successfully across compute01, compute02, compute03.

---

## Architecture

```
spartian-1 (Gentoo host, i7-12700F, 32GB RAM)
├── arm64-master      (192.168.56.10) — slurmctld, munge
│   └── /dev/vdb      — FTRFS 64 MiB data partition
├── arm64-compute01   (192.168.56.11) — slurmd
│   └── /dev/vdb      — FTRFS 64 MiB data partition
├── arm64-compute02   (192.168.56.12) — slurmd
│   └── /dev/vdb      — FTRFS 64 MiB data partition
└── arm64-compute03   (192.168.56.13) — slurmd
    └── /dev/vdb      — FTRFS 64 MiB data partition
```

## Component Versions

| Component    | Version        |
|--------------|----------------|
| Yocto        | Styhead (5.1)  |
| Slurm        | 25.11.4        |
| Munge        | 0.5.18         |
| PMIx         | 5.0.3          |
| OpenSSH      | 10.3p1         |
| MPICH        | (meta-oe)      |
| libevent     | 2.1.12         |
| Linux kernel | 7.0-rc7 mainline |
| FTRFS module | 0.1.0          |

## Branches

| Branch | Description |
|--------|-------------|
| `main` | System hardening D1-D7 (SELinux, dm-verity) |
| `yocto-hpc` | KVM HPC cluster x86-64 — Slurm 25.11.4 |
| `arm64-ftrfs` | arm64 HPC cluster with FTRFS data partition — **this branch** |

## Host Requirements

| Tool    | Version  |
|---------|----------|
| GCC     | 15.2.1   |
| Python  | 3.11.15  |
| glibc   | 2.42     |
| Git     | 2.52.0   |
| ninja   | 1.13+    |

> **Note:** This layer includes fixes for GCC 15 + glibc 2.42 + ninja 1.13
> incompatibilities that affect Yocto Styhead builds on a modern Gentoo host.

## Build

```bash
cd ~/yocto/poky
source oe-init-build-env build-qemu-arm64
bitbake hpc-arm64-master hpc-arm64-compute
```

## Images

| Image | Size | Contents |
|-------|------|----------|
| hpc-arm64-master | ~500 MB | slurmctld, munge, ftrfs-module |
| hpc-arm64-compute | ~311 MB | slurmd, munge, ftrfs-module |

## FTRFS Integration

Each node boots with a dedicated FTRFS partition on /dev/vdb.
The module is loaded and the partition mounted at runtime:

```bash
insmod /lib/modules/7.0.0-rc7/updates/ftrfs.ko
mkdir -p /var/tmp/ftrfs
mount -t ftrfs /dev/vdb /var/tmp/ftrfs
```

Format a FTRFS image from the host:

```bash
gcc -o mkfs.ftrfs mkfs.ftrfs.c
dd if=/dev/zero of=ftrfs.img bs=4096 count=16384
./mkfs.ftrfs ftrfs.img
```

FTRFS source: https://github.com/roastercode/FTRFS

## VM Deployment

```bash
DEPLOY=tmp/deploy/images/qemuarm64

sudo cp ${DEPLOY}/hpc-arm64-master-qemuarm64.ext4 \
    /var/lib/libvirt/images/hpc-arm64/arm64-master.ext4

for node in compute01 compute02 compute03; do
    sudo cp ${DEPLOY}/hpc-arm64-compute-qemuarm64.ext4 \
        /var/lib/libvirt/images/hpc-arm64/arm64-${node}.ext4
    sudo /path/to/mkfs.ftrfs \
        /var/lib/libvirt/images/hpc-arm64/ftrfs-${node}.img
done

sudo virsh start arm64-master
sudo virsh start arm64-compute01
sudo virsh start arm64-compute02
sudo virsh start arm64-compute03
```

## SSH Access

```bash
ssh -i ~/.ssh/hpclab_admin hpcadmin@192.168.56.10  # master
ssh -i ~/.ssh/hpclab_admin hpcadmin@192.168.56.11  # compute01
```

---

## Slurm 25.11.4 Cross-Compilation Patches (arm64)

| Patch | Issue fixed |
|-------|-------------|
| 0001 | -Wl,--allow-shlib-undefined on all plugins |
| 0002 | DEFAULT_PREP_PLUGINS="" — prep/script undefined symbol |
| 0003 | -Wl,--export-dynamic on slurmctld |
| 0004 | RTLD_LAZY\|RTLD_GLOBAL in plugin.c |
| 0005 | Stubs for internal slurmctld symbols in libslurmfull |

Binary symlinks: `aarch64-poky-linux-slurmctld` → `slurmctld` (TARGET_SYS).

## Slurm Runtime Configuration

- SlurmctldHost=master
- ProctrackType=proctrack/linuxproc (no cgroup dependency)
- CgroupPlugin=disabled (/etc/cgroup.conf)
- CPUs=4, RealMemory=462 (cortex-a57, 4 vCPU, 512 MiB)

---

## Cluster Status

- [x] SSH access (OpenSSH 10.3p1, ed25519 key)
- [x] Munge 0.5.18 — inter-node authentication
- [x] slurmctld — Slurm controller on master
- [x] slurmd — compute daemon on 3 nodes
- [x] sinfo — nodes idle
- [x] sbatch / srun — jobs running on compute[01-03]
- [x] FTRFS 0.1.0 — module loaded, partition mounted on all nodes
- [x] Benchmark — 9 jobs, perfect load balance

## TODO

1. Auto-start munge/slurm/ftrfs at boot via init.d
2. Static /etc/hosts in image (avoid manual setup)
3. NFS /scratch over FTRFS
4. Multi-node MPI tests

## Security Notes

- credentials.inc is never versioned
- Private SSH keys kept outside the repo
- SELinux permissive
- Read-only rootfs with overlayfs-etc on tmpfs
- dm-verity kernel support enabled
- hpcadmin with ed25519 key, sudo NOPASSWD, root SSH disabled
- munge.key: 1024 bytes random, root:root 0400
