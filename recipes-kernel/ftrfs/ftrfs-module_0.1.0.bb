SUMMARY = "FTRFS — Fault-Tolerant Radiation-Robust Filesystem kernel module"
DESCRIPTION = "Out-of-tree Linux kernel module implementing FTRFS. \
Based on: Fuchs, Langer, Trinitis - ARCS 2015 (TU Munich)"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=4c9369db79a4345d581e1a2b9b732941"

inherit module

SRC_URI = "file://ftrfs-0.1.0/"

S = "${WORKDIR}/ftrfs-0.1.0"

KERNEL_SRC = "${STAGING_KERNEL_DIR}"
KERNEL_PATH = "${STAGING_KERNEL_DIR}"

