# meta-custom

Couche Yocto custom pour Spartian-1. Scarthgap / poky-hardened.

## Branches

| Branche | Description |
|---------|-------------|
| `main` | Base minimale, point de départ |
| `ext4-dm-verity-selinux` | Image durcie : ext4 + dm-verity + SELinux enforcing + overlayfs-etc |
| `squashfs-selinux-permissive` | Image squashfs + SELinux permissive |
| `yocto-hpc` | Mini-cluster HPC virtuel (hérite de ext4-dm-verity-selinux) |

## Branche yocto-hpc

Construction d'un mini-labo HPC sur KVM/QEMU/libvirt pour tester
les commandes Slurm, MPI, NFS, modules, benchmarks.

### Architecture du cluster

| VM | IP | Rôle |
|----|----|------|
| master | 192.168.56.10 | Slurm controller, NFS server, login node |
| compute01 | 192.168.56.11 | Slurm worker, MPI |
| compute02 | 192.168.56.12 | Slurm worker, MPI |
| compute03 | 192.168.56.13 | Slurm worker, MPI |
| storage | 192.168.56.20 | NFS storage, /scratch |

### Images

| Image | Basée sur | Contenu |
|-------|-----------|---------|
| `hpc-image-master` | custom-image | slurm-slurmctld, munge, nfs-server, openmpi, lmod |
| `hpc-image-compute` | custom-image | slurm-slurmd, munge, nfs-client, openmpi |
| `hpc-image-storage` | custom-image | nfs-server, e2fsprogs |

### Recettes ajoutées

- `recipes-hpc/munge/` — authentification MUNGE
- `recipes-hpc/slurm/` — scheduler Slurm 23.x
- `recipes-hpc/openmpi/` — si non fourni par meta-oe (sinon mpich)
- `recipes-hpc/lmod/` — environment modules

### Stack logicielle hôte (Gentoo)

- KVM/QEMU 10.2.0
- libvirt 11.10.0 + virsh
- Réseau : hpcnet (192.168.56.0/24) via virbr1
- Firewall : nftables — cluster isolé, NAT vers wlo1 pour internet

## Distro

`poky-hardened` — hérite de poky avec :
- SELinux enforcing (refpolicy-targeted)
- dm-verity sur ext4
- read-only rootfs
- /etc writable via overlayfs tmpfs
- CVE checking activé
- Pas de debug-tweaks

## Prérequis build

BB_NUMBER_THREADS = "16"
PARALLEL_MAKE = "-j 16"
SSTATE_DIR = "${HOME}/yocto/sstate-cache"
DL_DIR = "${HOME}/yocto/downloads"

