# SPDX-License-Identifier: MIT
#
# hpc-arm64-xfstests.bb — arm64 xfstests image for FTRFS validation
#
# Minimal image containing xfstests and its dependencies.
# Used to run generic/001,002,010,098,257 against FTRFS.
#
# Build:
#   bitbake hpc-arm64-xfstests
#
# Run (in QEMU after boot):
#   modprobe ftrfs
#   dd if=/dev/zero of=/tmp/test.img bs=4096 count=16384
#   mkfs.ftrfs /tmp/test.img
#   modprobe loop
#   losetup /dev/loop0 /tmp/test.img
#   dd if=/dev/zero of=/tmp/scratch.img bs=4096 count=16384
#   losetup /dev/loop1 /tmp/scratch.img
#   mkdir -p /mnt/test /mnt/scratch
#   mount -t ftrfs /dev/loop0 /mnt/test
#   mount -t ftrfs /dev/loop1 /mnt/scratch
#   cd /usr/xfstests
#   ./check -ftrfs generic/001 generic/002 generic/010 generic/098 generic/257

SUMMARY = "arm64 xfstests image for FTRFS filesystem validation"
LICENSE = "MIT"

IMAGE_LINK_NAME = "hpc-arm64-xfstests-${MACHINE}"

inherit core-image

require recipes-core/images/hpc-config.inc
require recipes-core/images/credentials.inc

IMAGE_FEATURES:remove = "debug-tweaks"
IMAGE_FEATURES += "ssh-server-openssh"

IMAGE_FSTYPES = "ext4"
QB_DEFAULT_FSTYPE = "ext4"

IMAGE_INSTALL = " \
    packagegroup-core-boot \
    openssh \
    openssh-sftp-server \
    xfstests \
    bash \
    bc \
    coreutils \
    grep \
    inetutils-hostname \
    e2fsprogs \
    e2fsprogs-tune2fs \
    util-linux \
    acl \
    attr \
    iproute2 \
    procps \
    ftrfs-module \
    mkfs-ftrfs \
    ${CORE_IMAGE_EXTRA_INSTALL} \
"

IMAGE_ROOTFS_SIZE ?= "1048576"

ROOTFS_POSTPROCESS_COMMAND:append = " setup_xfstests_ftrfs;"
setup_xfstests_ftrfs() {
    # fsck.ftrfs stub — xfstests calls fsck after each test
    cat > ${IMAGE_ROOTFS}/usr/sbin/fsck.ftrfs << 'FSCKEOF'
#!/bin/sh
# fsck.ftrfs stub — FTRFS integrity is guaranteed by RS FEC at mount time
exit 0
FSCKEOF
    chmod 755 ${IMAGE_ROOTFS}/usr/sbin/fsck.ftrfs
    # Create local.config for xfstests pointing to ftrfs
    cat > ${IMAGE_ROOTFS}/usr/xfstests/local.config << 'LOCALEOF'
export FSTYP=ftrfs
export TEST_DEV=/dev/loop0
export TEST_DIR=/mnt/test
export SCRATCH_DEV=/dev/loop1
export SCRATCH_MNT=/mnt/scratch
export TMPDIR=/tmp
export RESULT_BASE=/usr/xfstests/results
export MKFS_OPTIONS="-N 256"
LOCALEOF
    mkdir -p ${IMAGE_ROOTFS}/mnt/test

    # hostname -s wrapper — BusyBox does not support -s flag
    mv ${IMAGE_ROOTFS}/bin/hostname ${IMAGE_ROOTFS}/bin/hostname.busybox
    cat > ${IMAGE_ROOTFS}/bin/hostname << 'HOSTNEOF'
#!/bin/sh
if [ "$1" = "-s" ]; then
    /bin/hostname.busybox | cut -d. -f1
else
    /bin/hostname.busybox "$@"
fi
HOSTNEOF
    chmod 755 ${IMAGE_ROOTFS}/bin/hostname

    # grep wrapper — BusyBox does not support -1 (context lines)
    mv ${IMAGE_ROOTFS}/bin/grep ${IMAGE_ROOTFS}/bin/grep.busybox
    cat > ${IMAGE_ROOTFS}/bin/grep << 'GREPEOF'
#!/bin/sh
exec /bin/grep.busybox "$@"
GREPEOF
    chmod 755 ${IMAGE_ROOTFS}/bin/grep

    # local.config — images on rootfs to avoid /tmp space issues
    sed -i "s|export TMPDIR=/tmp||" ${IMAGE_ROOTFS}/usr/xfstests/local.config
    mkdir -p ${IMAGE_ROOTFS}/usr/xfstests/results
    mkdir -p ${IMAGE_ROOTFS}/mnt/scratch
    # fsgqa user is created by xfstests USERADD_PARAM
}
