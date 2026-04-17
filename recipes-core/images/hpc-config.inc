# SPDX-License-Identifier: MIT
#
# hpc-config.inc — site-local HPC cluster configuration
#
# Copy this file to your build directory or include it from local.conf.
# All variables have defaults suitable for the reference QEMU lab setup.
#
# Usage in local.conf:
#   require /path/to/meta-yocto-hardened-hpc/recipes-core/images/hpc-config.inc
#
# Or override individual variables:
#   HPC_MASTER_IP = "10.0.0.10"

# Cluster name (used in slurm.conf ClusterName)
HPC_CLUSTER_NAME ?= "hpclab"

# Master node
HPC_MASTER_HOSTNAME ?= "arm64-master"
HPC_MASTER_IP       ?= "192.168.56.10"

# Compute nodes — extend as needed
HPC_COMPUTE01_HOSTNAME ?= "arm64-compute01"
HPC_COMPUTE01_IP       ?= "192.168.56.11"

HPC_COMPUTE02_HOSTNAME ?= "arm64-compute02"
HPC_COMPUTE02_IP       ?= "192.168.56.12"

HPC_COMPUTE03_HOSTNAME ?= "arm64-compute03"
HPC_COMPUTE03_IP       ?= "192.168.56.13"

# Compute node resources (adjust to match your QEMU/hardware config)
HPC_NODE_CPUS       ?= "4"
HPC_NODE_MEMORY_MB  ?= "462"

# Admin user created in the image
HPC_ADMIN_USER ?= "hpcadmin"

# SSH public key for the admin user.
# Set this to the path of your public key file, or leave empty to skip.
# Example:
#   HPC_ADMIN_PUBKEY_FILE = "${LAYERDIR}/files/my_admin_key.pub"
HPC_ADMIN_PUBKEY_FILE ?= "${THISDIR}/files/hpclab_admin.pub"

# Munge key file path.
# Generate with: dd if=/dev/urandom bs=1 count=1024 > munge.key
# Then set:
#   HPC_MUNGE_KEY_FILE = "${LAYERDIR}/files/munge.key"
HPC_MUNGE_KEY_FILE ?= "${THISDIR}/files/munge.key"
