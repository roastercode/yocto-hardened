SUMMARY = "Image HPC — nœud compute"
LICENSE = "MIT"

IMAGE_LINK_NAME = "hpc-image-compute-${MACHINE}"

inherit core-image dm-verity-image selinux-image

require recipes-core/images/credentials.inc

IMAGE_FEATURES:remove = "debug-tweaks"
IMAGE_FEATURES += "read-only-rootfs overlayfs-etc ssh-server-openssh"

OVERLAYFS_ETC_MOUNT_POINT = "/data"
OVERLAYFS_ETC_DEVICE = "tmpfs"
OVERLAYFS_ETC_FSTYPE = "tmpfs"

IMAGE_FSTYPES = "ext4"
VERITY_IMAGE_TYPE = "ext4"
QB_DEFAULT_FSTYPE = "ext4"

IMAGE_INSTALL = " \
    packagegroup-core-boot \
    packagegroup-selinux-minimal \
    openssh \
    nfs-utils \
    munge \
    slurm \
    slurm-slurmd \
    mpich \
    hwloc \
    procps \
    util-linux \
    ${CORE_IMAGE_EXTRA_INSTALL} \
"

IMAGE_ROOTFS_SIZE ?= "307200"

ROOTFS_POSTPROCESS_COMMAND:append = " create_hpc_dirs;"
create_hpc_dirs() {
    mkdir -p ${IMAGE_ROOTFS}/scratch
    mkdir -p ${IMAGE_ROOTFS}/data
    mkdir -p ${IMAGE_ROOTFS}/var/lib/slurm
    mkdir -p ${IMAGE_ROOTFS}/var/volatile/log/slurm
    mkdir -p ${IMAGE_ROOTFS}/etc/munge
    mkdir -p ${IMAGE_ROOTFS}/etc/slurm
}
