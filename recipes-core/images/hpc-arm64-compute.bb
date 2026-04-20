# SPDX-License-Identifier: MIT
#
# hpc-arm64-compute.bb — arm64 HPC compute node image
#
# Builds a hardened arm64 image for Slurm compute nodes.
# FTRFS is mounted as a dedicated data partition (/dev/vdb).
#
# Prerequisites:
#   - Copy credentials.inc.example to credentials.inc and set your password
#   - Set HPC_ADMIN_PUBKEY_FILE and HPC_MUNGE_KEY_FILE in hpc-config.inc
#     or in your local.conf
#
# Build:
#   bitbake hpc-arm64-compute

SUMMARY = "HPC arm64 compute node — hardened image with FTRFS"
LICENSE = "MIT"

IMAGE_LINK_NAME = "hpc-arm64-compute-${MACHINE}"

inherit core-image dm-verity-image

require recipes-core/images/hpc-config.inc

# credentials.inc is site-local and not tracked in git.
# Copy credentials.inc.example to credentials.inc before building.
require recipes-core/images/credentials.inc

IMAGE_FEATURES:remove = "debug-tweaks"
IMAGE_FEATURES += "read-only-rootfs overlayfs-etc ssh-server-openssh"

OVERLAYFS_ETC_MOUNT_POINT = "/data"
OVERLAYFS_ETC_DEVICE      = "tmpfs"
OVERLAYFS_ETC_FSTYPE      = "tmpfs"

IMAGE_FSTYPES     = "ext4"
VERITY_IMAGE_TYPE = "ext4"
QB_DEFAULT_FSTYPE = "ext4"

IMAGE_INSTALL = " \
    packagegroup-core-boot \
    openssh \
    nfs-utils \
    munge \
    slurm \
    slurm-slurmd \
    hwloc \
    procps \
    util-linux \
    sudo \
    iproute2 \
    strace \
    lsof \
    ftrfs-module \
    mkfs-ftrfs \
    ftrfsd \
    ${CORE_IMAGE_EXTRA_INSTALL} \
"

IMAGE_ROOTFS_SIZE ?= "307200"

# Create HPC directory structure
ROOTFS_POSTPROCESS_COMMAND:append = " create_hpc_dirs;"
create_hpc_dirs() {
    mkdir -p ${IMAGE_ROOTFS}/scratch
    mkdir -p ${IMAGE_ROOTFS}/data
    mkdir -p ${IMAGE_ROOTFS}/var/lib/slurm
    mkdir -p ${IMAGE_ROOTFS}/var/volatile/log/slurm
    mkdir -p ${IMAGE_ROOTFS}/etc/munge
    mkdir -p ${IMAGE_ROOTFS}/etc/slurm
}

# Basic network configuration
ROOTFS_POSTPROCESS_COMMAND:append = " setup_hpc_network;"
setup_hpc_network() {
    cat >> ${IMAGE_ROOTFS}/etc/network/interfaces << 'NETEOF'
auto eth0
iface eth0 inet dhcp
NETEOF
}

# Generate SSH host keys at build time
ROOTFS_POSTPROCESS_COMMAND:append = " preseed_ssh_keys;"
preseed_ssh_keys() {
    export PATH="/usr/bin:${PATH}"
    ssh-keygen -t rsa     -b 2048 -f ${IMAGE_ROOTFS}/etc/ssh/ssh_host_rsa_key    -N "" -C ""
    ssh-keygen -t ecdsa           -f ${IMAGE_ROOTFS}/etc/ssh/ssh_host_ecdsa_key   -N "" -C ""
    ssh-keygen -t ed25519         -f ${IMAGE_ROOTFS}/etc/ssh/ssh_host_ed25519_key  -N "" -C ""
    chmod 600 ${IMAGE_ROOTFS}/etc/ssh/ssh_host_rsa_key \
              ${IMAGE_ROOTFS}/etc/ssh/ssh_host_ecdsa_key \
              ${IMAGE_ROOTFS}/etc/ssh/ssh_host_ed25519_key
}

# Create admin user and install SSH public key if provided
ROOTFS_POSTPROCESS_COMMAND:append = " setup_hpcadmin;"
setup_hpcadmin() {
    useradd -R ${IMAGE_ROOTFS} -m -s /bin/sh -G sudo ${HPC_ADMIN_USER} 2>/dev/null || true
    mkdir -p ${IMAGE_ROOTFS}/home/${HPC_ADMIN_USER}/.ssh
    chmod 700 ${IMAGE_ROOTFS}/home/${HPC_ADMIN_USER}/.ssh
    if [ -n "${HPC_ADMIN_PUBKEY_FILE}" ] && [ -f "${HPC_ADMIN_PUBKEY_FILE}" ]; then
        cp ${HPC_ADMIN_PUBKEY_FILE} \
            ${IMAGE_ROOTFS}/home/${HPC_ADMIN_USER}/.ssh/authorized_keys
        chmod 600 ${IMAGE_ROOTFS}/home/${HPC_ADMIN_USER}/.ssh/authorized_keys
        chown -R 1000:1000 ${IMAGE_ROOTFS}/home/${HPC_ADMIN_USER}/.ssh
    fi
    mkdir -p ${IMAGE_ROOTFS}/etc/sudoers.d
    echo "${HPC_ADMIN_USER} ALL=(ALL) NOPASSWD: ALL" > \
        ${IMAGE_ROOTFS}/etc/sudoers.d/${HPC_ADMIN_USER}
    chmod 440 ${IMAGE_ROOTFS}/etc/sudoers.d/${HPC_ADMIN_USER}
}

# Install munge key if provided
ROOTFS_POSTPROCESS_COMMAND:append = " preseed_munge_key;"
preseed_munge_key() {
    if [ -n "${HPC_MUNGE_KEY_FILE}" ] && [ -f "${HPC_MUNGE_KEY_FILE}" ]; then
        install -m 0400 ${HPC_MUNGE_KEY_FILE} ${IMAGE_ROOTFS}/etc/munge/munge.key
        chown 0:0 ${IMAGE_ROOTFS}/etc/munge/munge.key
    fi
    chmod 0700 ${IMAGE_ROOTFS}/etc/munge
    chown 0:0 ${IMAGE_ROOTFS}/etc/munge
}

# Set hostname and /etc/hosts — compute nodes share the same image,
# hostname is set at first boot via cloud-init or manual configuration.
# Default to compute01 for QEMU single-node testing.
ROOTFS_POSTPROCESS_COMMAND:append = " setup_hostname_compute;"
setup_hostname_compute() {
    echo "${HPC_COMPUTE01_HOSTNAME}" > ${IMAGE_ROOTFS}/etc/hostname
    cat >> ${IMAGE_ROOTFS}/etc/hosts << HOSTSEOF
${HPC_MASTER_IP} ${HPC_MASTER_HOSTNAME}
${HPC_COMPUTE01_IP} ${HPC_COMPUTE01_HOSTNAME}
${HPC_COMPUTE02_IP} ${HPC_COMPUTE02_HOSTNAME}
${HPC_COMPUTE03_IP} ${HPC_COMPUTE03_HOSTNAME}
HOSTSEOF
    ln -sf /etc/slurm/slurm.conf ${IMAGE_ROOTFS}/etc/slurm.conf 2>/dev/null || true
}
