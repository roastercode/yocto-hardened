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

Construction d'un mini-labo HPC sur KVM/QEMU/libvirt pour apprendre
l'administration HPC : Slurm, MPI, NFS, benchmarks, environnements modules.

### Architecture du cluster

| VM | IP | Rôle |
|----|----|------|
| master | 192.168.56.10 | Slurm controller, NFS server, login node |
| compute01 | 192.168.56.11 | Slurm worker, MPI |
| compute02 | 192.168.56.12 | Slurm worker, MPI |
| compute03 | 192.168.56.13 | Slurm worker, MPI |
| storage | 192.168.56.20 | NFS storage, /scratch |

### Images

| Image | Taille | Contenu principal |
|-------|--------|-------------------|
| `hpc-image-master` | ~500 Mo | slurmctld, munge, nfs-server, mpich, htop |
| `hpc-image-compute` | ~300 Mo | slurmd, munge, nfs-client, mpich, hwloc |
| `hpc-image-storage` | ~206 Mo | nfs-server, e2fsprogs |

### Recettes HPC

| Recette | Version | Notes |
|---------|---------|-------|
| `recipes-hpc/libevent/` | 2.1.12 | Dépendance munge/slurm |
| `recipes-hpc/munge/` | 0.5.15 | Auth cluster, 2 patches cross-compile |
| `recipes-hpc/pmix/` | 5.0.3 | Process Management Interface |
| `recipes-hpc/slurm/` | 23.11.7 | Ordonnanceur HPC (sans PAM/MySQL/sview) |

### État du cluster

| Composant | État |
|-----------|------|
| VMs KVM (5 nœuds) | ✅ Opérationnel |
| Réseau hpcnet (192.168.56.0/24) | ✅ DHCP fonctionnel |
| SSH par clé ed25519 (hpcadmin) | ✅ Fonctionnel sur les 5 nœuds |
| sudo sans mot de passe (hpcadmin) | ✅ Configuré |
| SELinux | ⚠️ Permissif (labo) — overlayfs+tmpfs incompatible enforcing |
| Munge | 🔧 À configurer |
| Slurm | 🔧 À configurer |
| NFS /scratch | 🔧 À configurer |

### Accès SSH

```bash
ssh -i ~/.ssh/hpclab_admin hpcadmin@192.168.56.10  # master
ssh -i ~/.ssh/hpclab_admin hpcadmin@192.168.56.11  # compute01
ssh -i ~/.ssh/hpclab_admin hpcadmin@192.168.56.20  # storage
```

La clé privée `~/.ssh/hpclab_admin` n'est jamais versionnée.
La clé publique est dans `recipes-core/images/files/hpclab_admin.pub`.

### Patches cross-compilation (hôte Gentoo)

- `munge/0001` — fix `AC_RUN_IFELSE` test fifo (impossible en cross-compile)
- `munge/0002` — fix `AC_CHECK_FILES /dev/spx` (Linux n'a pas /dev/spx)
- `slurm` — désactivation sview/glib (`AM_PATH_GLIB_2_0` non disponible)
- `INSANE_SKIP += configure-unsafe` — warning linker `/usr/lib` hôte Gentoo

### Stack logicielle hôte (Gentoo spartian-1)

- CPU : 20 cœurs, 32 Go RAM, NVMe 512 Go
- KVM/QEMU 10.2.0, libvirt 11.10.0
- Réseau : hpcnet (192.168.56.0/24) via virbr1
- Firewall : nftables — cluster isolé, NAT vers wlo1

### Roadmap

Phase 1 — Infrastructure (done)
✅ Build des 3 images Yocto (libevent, munge, pmix, slurm)
✅ 5 VMs KVM avec réseau et SSH fonctionnels
✅ hpcadmin avec clé SSH et sudo

Phase 2 — Services HPC (en cours)
🔧 Munge — clé partagée sur tous les nœuds
🔧 Slurm — slurmctld master + slurmd computes
🔧 NFS — /scratch depuis storage

Phase 3 — Workloads HPC
🔲 Tests MPI (mpirun, mpiexec)
🔲 Benchmarks (STREAM, IOR, HPL)
🔲 Environment modules (lmod)
🔲 Gestion des jobs (sbatch, squeue, sacct)


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

