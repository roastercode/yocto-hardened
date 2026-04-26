# SPDX-License-Identifier: MIT
#
# hpc-arm64-research.bb -- arm64 HPC research image (all-in-one)
#
# Builds a research-grade arm64 image that combines master controller
# and compute node functionality into a single squashfs rootfs. The
# same image is deployed on every node of the cluster; hostname is
# selected at boot time from the kernel command line via the
# /etc/init.d/S01hostname-cmdline init script (kernel cmdline:
# ftrfs.hostname=<name>).
#
# This image is the reference deployment for the FTRFS research
# benchmark and replaces hpc-arm64-master.bb + hpc-arm64-compute.bb
# for new work. The legacy recipes are kept for backwards compatibility
# until the research image is fully validated.
#
# Hardening posture:
#   - rootfs: squashfs (read-only by construction)
#   - /etc:   tmpfs overlay (overlayfs-etc)
#   - /data:  real FTRFS partition on /dev/vdb (NOT loopback)
#
# TODO: dm-verity over the squashfs rootfs (planned for future research
# session, tracked in Documentation/roadmap.md).
#
# Bench tooling included beyond the legacy hpc-arm64-* images:
#   bash, gawk, coreutils, bc, time, iperf3, fio, sysstat,
#   strace.
#
# Prerequisites:
#   - Copy credentials.inc.example to credentials.inc and set your password
#   - Set HPC_ADMIN_PUBKEY_FILE and HPC_MUNGE_KEY_FILE in hpc-config.inc
#     or in your local.conf
#
# Build:
#   bitbake hpc-arm64-research
#
# QEMU boot example:
#   qemu-system-aarch64 ... -append "root=/dev/vda ftrfs.hostname=arm64-master ..."

SUMMARY = "HPC arm64 research image -- all-in-one (master+compute) with FTRFS bench tools"
LICENSE = "MIT"

IMAGE_LINK_NAME = "hpc-arm64-research-${MACHINE}"

inherit core-image

require recipes-core/images/hpc-config.inc
require recipes-core/images/credentials.inc

IMAGE_FEATURES:remove = "debug-tweaks"
IMAGE_FEATURES += "read-only-rootfs overlayfs-etc ssh-server-openssh"

# overlayfs-etc tunables. Semantically:
#   OVERLAYFS_ETC_MOUNT_POINT is the location where the upper layer
#   of the overlay is stored. We point it at /run/overlay-etc which
#   is a tmpfs (volatile per boot). EXPOSE_LOWER=1 is REQUIRED so the
#   original /etc content from the squashfs rootfs is bind-mounted RO
#   under $LOWER_DIR; otherwise the overlay sees only an empty tmpfs
#   and init(1) cannot read /etc/inittab.
OVERLAYFS_ETC_MOUNT_POINT = "/run/overlay-etc"
OVERLAYFS_ETC_DEVICE      = "tmpfs"
OVERLAYFS_ETC_FSTYPE      = "tmpfs"
OVERLAYFS_ETC_EXPOSE_LOWER = "1"

# rootfs is squashfs (read-only by construction). The legacy ext4 +
# dm-verity stack is preserved as a future research item; for now,
# squashfs gives us read-only without verified-boot machinery.
IMAGE_FSTYPES   = "squashfs"
QB_DEFAULT_FSTYPE = "squashfs"

IMAGE_INSTALL = " \
    packagegroup-core-boot \
    openssh \
    openssh-sftp-server \
    nfs-utils \
    munge \
    slurm \
    slurm-slurmctld \
    slurm-slurmd \
    hwloc \
    htop \
    procps \
    util-linux \
    sudo \
    iproute2 \
    strace \
    lsof \
    bash \
    gawk \
    coreutils \
    bc \
    time \
    iperf3 \
    fio \
    sysstat \
    parted \
    e2fsprogs \
    ftrfs-module \
    mkfs-ftrfs \
    ftrfsd \
    ${CORE_IMAGE_EXTRA_INSTALL} \
"

# Larger rootfs to absorb the bench tooling (~80 MB total budget).
IMAGE_ROOTFS_SIZE ?= "768000"

# ------------------------------------------------------------------
# HPC directory structure
# ------------------------------------------------------------------
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

# ------------------------------------------------------------------
# Network: dhcp on eth0
# ------------------------------------------------------------------
ROOTFS_POSTPROCESS_COMMAND:append = " setup_hpc_network;"
setup_hpc_network() {
    cat >> ${IMAGE_ROOTFS}/etc/network/interfaces << 'NETEOF'
auto eth0
iface eth0 inet dhcp
NETEOF
}

# ------------------------------------------------------------------
# Pre-seeded SSH host keys (for reproducible deployment)
# ------------------------------------------------------------------
ROOTFS_POSTPROCESS_COMMAND:append = " preseed_ssh_keys;"
preseed_ssh_keys() {
    export PATH="/usr/bin:${PATH}"
    ssh-keygen -t rsa     -b 2048 -f ${IMAGE_ROOTFS}/etc/ssh/ssh_host_rsa_key     -N "" -C ""
    ssh-keygen -t ecdsa           -f ${IMAGE_ROOTFS}/etc/ssh/ssh_host_ecdsa_key   -N "" -C ""
    ssh-keygen -t ed25519         -f ${IMAGE_ROOTFS}/etc/ssh/ssh_host_ed25519_key -N "" -C ""
    chmod 600 ${IMAGE_ROOTFS}/etc/ssh/ssh_host_rsa_key \
              ${IMAGE_ROOTFS}/etc/ssh/ssh_host_ecdsa_key \
              ${IMAGE_ROOTFS}/etc/ssh/ssh_host_ed25519_key
}

# ------------------------------------------------------------------
# Admin user + sudo
# ------------------------------------------------------------------
ROOTFS_POSTPROCESS_COMMAND:append = " setup_hpcadmin;"
setup_hpcadmin() {
    useradd -R ${IMAGE_ROOTFS} -m -s /bin/bash -G sudo ${HPC_ADMIN_USER} 2>/dev/null || true
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

# ------------------------------------------------------------------
# Munge key (cluster-wide shared secret)
# ------------------------------------------------------------------
ROOTFS_POSTPROCESS_COMMAND:append = " preseed_munge_key;"
preseed_munge_key() {
    if [ -n "${HPC_MUNGE_KEY_FILE}" ] && [ -f "${HPC_MUNGE_KEY_FILE}" ]; then
        install -m 0400 ${HPC_MUNGE_KEY_FILE} ${IMAGE_ROOTFS}/etc/munge/munge.key
        chown 0:0 ${IMAGE_ROOTFS}/etc/munge/munge.key
    fi
    chmod 0700 ${IMAGE_ROOTFS}/etc/munge
    chown 0:0 ${IMAGE_ROOTFS}/etc/munge
}

# ------------------------------------------------------------------
# /etc/hosts (static cluster topology)
# Hostname itself is set at boot from the kernel command line
# (see install_hostname_init below). The image does NOT pre-write
# /etc/hostname; that file is created at first boot by the init
# script using ftrfs.hostname=<name> from /proc/cmdline.
# ------------------------------------------------------------------
ROOTFS_POSTPROCESS_COMMAND:append = " setup_hosts_static;"
setup_hosts_static() {
    cat >> ${IMAGE_ROOTFS}/etc/hosts << HOSTSEOF
${HPC_MASTER_IP} ${HPC_MASTER_HOSTNAME}
${HPC_COMPUTE01_IP} ${HPC_COMPUTE01_HOSTNAME}
${HPC_COMPUTE02_IP} ${HPC_COMPUTE02_HOSTNAME}
${HPC_COMPUTE03_IP} ${HPC_COMPUTE03_HOSTNAME}
HOSTSEOF
    ln -sf /etc/slurm/slurm.conf ${IMAGE_ROOTFS}/etc/slurm.conf 2>/dev/null || true
}

# ------------------------------------------------------------------
# Hostname-from-cmdline init script (OpenRC-compatible)
# Reads the kernel command line, looks for a token of the form
# ftrfs.hostname=<name>, and applies it via hostname(1) and
# /etc/hostname write. Falls back to a default (research-node) if
# the token is missing.
# ------------------------------------------------------------------
ROOTFS_POSTPROCESS_COMMAND:append = " install_hostname_init;"
install_hostname_init() {
    cat > ${IMAGE_ROOTFS}/etc/init.d/S01hostname-cmdline << 'INITEOF'
#!/bin/sh
# S01hostname-cmdline -- set hostname from kernel command line
# Looks for ftrfs.hostname=<name> in /proc/cmdline.
# Default fallback: research-node.
HN=$(awk -v RS=' ' '/^ftrfs\.hostname=/{sub(/^ftrfs\.hostname=/, ""); print}' /proc/cmdline 2>/dev/null)
if [ -z "$HN" ]; then
    HN="research-node"
fi
echo "$HN" > /etc/hostname
hostname "$HN"
INITEOF
    chmod 0755 ${IMAGE_ROOTFS}/etc/init.d/S01hostname-cmdline
    # Activate at sysinit runlevel (rcS.d) so hostname is set
    # before any other script reads /etc/hostname. S01 prefix
    # ensures it runs first, before networking, before the Yocto
    # hostname.sh init script, and before the read-only-rootfs hook.
    mkdir -p ${IMAGE_ROOTFS}/etc/rcS.d
    ln -sf ../init.d/S01hostname-cmdline \
        ${IMAGE_ROOTFS}/etc/rcS.d/S01hostname-cmdline
}

# ------------------------------------------------------------------
# slurm.conf (master role + compute nodes declared statically)
# ------------------------------------------------------------------
ROOTFS_POSTPROCESS_COMMAND:append = " setup_slurm_conf;"
setup_slurm_conf() {
    CONF=${IMAGE_ROOTFS}/etc/slurm/slurm.conf
    install -m 0644 \
        ${THISDIR}/../../recipes-hpc/slurm/files/slurm.conf \
        ${CONF}
    sed -i "s|@HPC_CLUSTER_NAME@|${HPC_CLUSTER_NAME}|g"       ${CONF}
    sed -i "s|@HPC_MASTER_HOSTNAME@|${HPC_MASTER_HOSTNAME}|g"  ${CONF}
    cat >> ${CONF} << SLURMEOF
NodeName=${HPC_COMPUTE01_HOSTNAME} NodeAddr=${HPC_COMPUTE01_IP} CPUs=${HPC_NODE_CPUS} RealMemory=${HPC_NODE_MEMORY_MB} State=UNKNOWN
NodeName=${HPC_COMPUTE02_HOSTNAME} NodeAddr=${HPC_COMPUTE02_IP} CPUs=${HPC_NODE_CPUS} RealMemory=${HPC_NODE_MEMORY_MB} State=UNKNOWN
NodeName=${HPC_COMPUTE03_HOSTNAME} NodeAddr=${HPC_COMPUTE03_IP} CPUs=${HPC_NODE_CPUS} RealMemory=${HPC_NODE_MEMORY_MB} State=UNKNOWN
PartitionName=compute Nodes=${HPC_COMPUTE01_HOSTNAME},${HPC_COMPUTE02_HOSTNAME},${HPC_COMPUTE03_HOSTNAME} Default=YES MaxTime=4:00:00 State=UP
SLURMEOF
}
