SUMMARY = "Image HPC — nœud storage NFS"
LICENSE = "MIT"

IMAGE_LINK_NAME = "hpc-image-storage-${MACHINE}"

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
    e2fsprogs \
    procps \
    util-linux \
    ${CORE_IMAGE_EXTRA_INSTALL} \
"

IMAGE_ROOTFS_SIZE ?= "204800"

ROOTFS_POSTPROCESS_COMMAND:append = " create_storage_dirs;"
create_storage_dirs() {
    mkdir -p ${IMAGE_ROOTFS}/scratch
    mkdir -p ${IMAGE_ROOTFS}/data
    mkdir -p ${IMAGE_ROOTFS}/exports
}
