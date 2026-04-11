# Yocto HPC Layer

Couche Yocto custom pour un cluster HPC mini-labo basé sur KVM/QEMU, Slurm, MPI et NFS.

## Architecture

(Gentoo, host)

  ├── hpc-master      (192.168.56.10) — slurmctld, nfs-server

  ├── hpc-compute01   (192.168.56.11) — slurmd
  
  ├── hpc-compute02   (192.168.56.12) — slurmd
  
  ├── hpc-compute03   (192.168.56.13) — slurmd
  
  └── hpc-storage     (192.168.56.20) — nfs-server, scratch


## Versions

| Composant | Version |
|-----------|---------|
| Yocto     | Scarthgap (5.0) |
| Slurm     | 25.11.4 |
| Munge     | 0.5.15 |
| PMIx      | 5.0.3 |
| MPICH     | (meta-oe) |
| libevent  | 2.1.12 |

## Branches

| Branche | Description |
|---------|-------------|
| `main` | Hardening D1-D7 (SELinux, dm-verity) |
| `yocto-hpc` | Cluster HPC KVM — **branche active** |

## Build

```bash
source poky/oe-init-build-env build-qemu-x86
bitbake hpc-image-master hpc-image-compute hpc-image-storage
```

## Images

| Image | Taille | Contenu |
|-------|--------|---------|
| hpc-image-master | ~500 Mo | slurmctld, munge, nfs-server, mpich |
| hpc-image-compute | ~300 Mo | slurmd, munge, nfs-client, mpich, hwloc |
| hpc-image-storage | ~206 Mo | nfs-server, e2fsprogs |

## Déploiement VMs

```bash
DEPLOY=tmp/deploy/images/qemux86-64
sudo qemu-img convert -f raw -O qcow2 \
  ${DEPLOY}/hpc-image-master-qemux86-64.ext4 \
  /var/lib/libvirt/images/hpclab/master.qcow2
```

## Accès SSH

```bash
ssh -i ~/.ssh/hpclab_admin hpcadmin@192.168.56.10  # master
ssh -i ~/.ssh/hpclab_admin hpcadmin@192.168.56.11  # compute01
```

## Cross-compilation Slurm — Patches

Slurm 25.11.4 nécessite 5 patches pour compiler et fonctionner en cross-compilation Yocto :

| Patch | Problème résolu |
|-------|----------------|
| 0001 | `-Wl,--allow-shlib-undefined` sur plugins hdf5 et pmix (97/99 déjà fixés upstream) |
| 0002 | `DEFAULT_PREP_PLUGINS=""` — prep/script utilise un symbole interne slurmd |
| 0003 | `-Wl,--export-dynamic` sur slurmctld pour exposer ses symboles aux plugins |
| 0004 | `RTLD_LAZY\|RTLD_GLOBAL` dans plugin.c pour la résolution de symboles inter-plugins |
| 0005 | Stubs des symboles internes slurmctld dans libslurmfull pour les outils clients |

Fork Slurm avec patches : https://github.com/roastercode/slurm/tree/fix/cross-compile-plugin-symbols

## État du cluster

- [x] Munge — authentification inter-nœuds
- [x] slurmctld — contrôleur Slurm sur master
- [x] slurmd — daemon compute sur 3 nœuds
- [x] sinfo — nœuds idle
- [x] sbatch — jobs exécutés sur compute01-03
- [ ] cgroup v1 au boot (montage manuel requis)
- [ ] NFS /scratch
- [ ] Tests MPI multi-nœuds

## TODO

1. Intégrer montage cgroup v1 dans hpc-image-compute (fstab ou script init)
2. Configurer NFS /scratch depuis hpc-storage
3. Tests MPI multi-nœuds avec mpich
4. Bug report SchedMD : https://support.schedmd.com/

## Sécurité

- credentials.inc jamais versionné
- Clés SSH privées hors repo
- SELinux permissif (overlayfs + tmpfs incompatible enforcing)
- hpcadmin avec clé ed25519, sudo NOPASSWD, root SSH désactivé
