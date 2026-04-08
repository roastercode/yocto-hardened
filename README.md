# Yocto HPC

Couche Yocto custom Scarthgap / poky-hardened.

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
| `hpc-image-master` | custom-image | slurm-slurmctld, munge, nfs-server, mpich |
| `hpc-image-compute` | custom-image | slurm-slurmd, munge, nfs-client, mpich |
| `hpc-image-storage` | custom-image | nfs-server, e2fsprogs |

### Recettes ajoutées

| Recette | Version | Notes |
|---------|---------|-------|
| `recipes-hpc/libevent/` | 2.1.12 | Dépendance munge/slurm |
| `recipes-hpc/munge/` | 0.5.15 | Auth cluster, 2 patches cross-compile |
| `recipes-hpc/pmix/` | 5.0.3 | Process Management Interface |
| `recipes-hpc/slurm/` | 23.11.7 | Ordonnanceur HPC |

### Patches cross-compilation (hôte Gentoo)

- `munge/0001` — fix `AC_RUN_IFELSE` test fifo (impossible en cross-compile)
- `munge/0002` — fix `AC_CHECK_FILES /dev/spx` (Linux n'a pas /dev/spx)
- `slurm` — désactivation sview/glib (`AM_PATH_GLIB_2_0` non disponible)
- `INSANE_SKIP += configure-unsafe` — warning linker `/usr/lib` hôte Gentoo

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
- PAM activé
- Pas de debug-tweaks
- Gentoo ajouté aux distros validées (`SANITY_TESTED_DISTROS`)

## Prérequis build

BB_NUMBER_THREADS = "16"
PARALLEL_MAKE = "-j 16"
SSTATE_DIR = "${HOME}/yocto/sstate-cache"
DL_DIR = "${HOME}/yocto/downloads"

