SUMMARY = "Image HPC arm64 — nœud master / login"
LICENSE = "MIT"
IMAGE_LINK_NAME = "hpc-arm64-master-${MACHINE}"
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
    openssh-sftp-server \
    nfs-utils \
    munge \
    slurm \
    slurm-slurmctld \
    mpich \
    hwloc \
    htop \
    procps \
    util-linux \
    sudo \
    iproute2 \
    strace \
    lsof \
    nmap \
    ftrfs-module \
    ${CORE_IMAGE_EXTRA_INSTALL} \
"
IMAGE_ROOTFS_SIZE ?= "512000"
ROOTFS_POSTPROCESS_COMMAND:append = " create_hpc_dirs;"
create_hpc_dirs() {
    mkdir -p ${IMAGE_ROOTFS}/scratch
    mkdir -p ${IMAGE_ROOTFS}/data
    mkdir -p ${IMAGE_ROOTFS}/var/lib/slurm
    mkdir -p ${IMAGE_ROOTFS}/var/log/slurm || true
    mkdir -p ${IMAGE_ROOTFS}/var/volatile/log/slurm
    mkdir -p ${IMAGE_ROOTFS}/etc/munge
    mkdir -p ${IMAGE_ROOTFS}/etc/slurm
}
ROOTFS_POSTPROCESS_COMMAND:append = " setup_hpc_network;"
setup_hpc_network() {
    cat >> ${IMAGE_ROOTFS}/etc/network/interfaces << 'NETEOF'
auto eth0
iface eth0 inet dhcp
NETEOF
}
ROOTFS_POSTPROCESS_COMMAND:append = " preseed_ssh_keys;"
preseed_ssh_keys() {
    export PATH="/usr/bin:${PATH}"
    ssh-keygen -t rsa -b 2048 -f ${IMAGE_ROOTFS}/etc/ssh/ssh_host_rsa_key -N "" -C ""
    ssh-keygen -t ecdsa -f ${IMAGE_ROOTFS}/etc/ssh/ssh_host_ecdsa_key -N "" -C ""
    ssh-keygen -t ed25519 -f ${IMAGE_ROOTFS}/etc/ssh/ssh_host_ed25519_key -N "" -C ""
    chmod 600 ${IMAGE_ROOTFS}/etc/ssh/ssh_host_rsa_key \
              ${IMAGE_ROOTFS}/etc/ssh/ssh_host_ecdsa_key \
              ${IMAGE_ROOTFS}/etc/ssh/ssh_host_ed25519_key
    if [ -f ${IMAGE_ROOTFS}/etc/selinux/config ]; then
        sed -i 's/SELINUX=enforcing/SELINUX=permissive/' ${IMAGE_ROOTFS}/etc/selinux/config
    fi
}
ROOTFS_POSTPROCESS_COMMAND:append = " setup_hpcadmin;"
setup_hpcadmin() {
    useradd -R ${IMAGE_ROOTFS} -m -s /bin/bash -G sudo hpcadmin 2>/dev/null || true
    mkdir -p ${IMAGE_ROOTFS}/home/hpcadmin/.ssh
    chmod 700 ${IMAGE_ROOTFS}/home/hpcadmin/.ssh
    cp ${THISDIR}/files/hpclab_admin.pub \
        ${IMAGE_ROOTFS}/home/hpcadmin/.ssh/authorized_keys
    chmod 600 ${IMAGE_ROOTFS}/home/hpcadmin/.ssh/authorized_keys
    chown -R 1000:1000 ${IMAGE_ROOTFS}/home/hpcadmin/.ssh
    mkdir -p ${IMAGE_ROOTFS}/etc/sudoers.d
    echo "hpcadmin ALL=(ALL) NOPASSWD: ALL" > \
        ${IMAGE_ROOTFS}/etc/sudoers.d/hpcadmin
    chmod 440 ${IMAGE_ROOTFS}/etc/sudoers.d/hpcadmin
}
ROOTFS_POSTPROCESS_COMMAND:append = " preseed_munge_key;"
preseed_munge_key() {
    install -m 0400 ${THISDIR}/files/munge.key ${IMAGE_ROOTFS}/etc/munge/munge.key
    chown 0:0 ${IMAGE_ROOTFS}/etc/munge/munge.key
    chmod 0700 ${IMAGE_ROOTFS}/etc/munge
    chown 0:0 ${IMAGE_ROOTFS}/etc/munge
}
ROOTFS_POSTPROCESS_COMMAND:append = " setup_hostname_master;"
setup_hostname_master() {
    echo "arm64-master" > ${IMAGE_ROOTFS}/etc/hostname
    cat >> ${IMAGE_ROOTFS}/etc/hosts << 'HOSTSEOF'
192.168.57.10 arm64-master
192.168.57.11 arm64-compute01
192.168.57.12 arm64-compute02
192.168.57.13 arm64-compute03
HOSTSEOF
    ln -sf /etc/slurm/slurm.conf ${IMAGE_ROOTFS}/etc/slurm.conf 2>/dev/null || true
}
