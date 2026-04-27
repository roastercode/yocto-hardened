SUMMARY = "Linux kernel 7.0.1 stable (kernel.org linux-7.0.y branch)"
DESCRIPTION = "Linux 7.0 stable kernel from kernel.org linux-stable.git, branch linux-7.0.y"
SECTION = "kernel"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=6bc538ed5bd9a7fc9398086aedcd7e46"

inherit kernel

# CVE exclusions: 88 pre-v7.0 CVEs marked as fixed-version (Patched)
# See cve-exclusions-kernel.inc for justification.
require cve-exclusions-kernel.inc

SRCREV = "3cb1fb7a56d2fd8011f5282bc170c0d23dc1f4b5"
KBRANCH = "linux-7.0.y"

SRC_URI = "git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git;branch=linux-7.0.y;protocol=https"

S = "${WORKDIR}/git"

LINUX_VERSION = "7.0.1"
LINUX_VERSION_EXTENSION = "-mainline"
PV = "7.0.1"

KERNEL_FEATURES:append = " cfg/fs/vfat.scc"

COMPATIBLE_MACHINE = "qemux86-64"

FILESEXTRAPATHS:prepend := "${THISDIR}:"
SRC_URI:append = " file://dm-verity.cfg"

do_configure:append() {
    ${S}/scripts/kconfig/merge_config.sh -m -O ${B} ${B}/.config ${UNPACKDIR}/dm-verity.cfg
    yes '' | make -C ${S} O=${B} oldconfig
}

# arm64 support
COMPATIBLE_MACHINE:append = "|qemuarm64"

SRC_URI:append:qemuarm64 = " file://ftrfs-arm64.cfg"

do_configure:append:qemuarm64() {
    ${S}/scripts/kconfig/merge_config.sh -m -O ${B} ${B}/.config ${UNPACKDIR}/ftrfs-arm64.cfg
    yes '' | make -C ${S} O=${B} oldconfig
}
