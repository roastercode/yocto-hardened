SUMMARY = "Linux kernel 7.0-rc7 (Linus Torvalds mainline)"
DESCRIPTION = "Linux mainline kernel tracking Linus's tree"
SECTION = "kernel"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=6bc538ed5bd9a7fc9398086aedcd7e46"

inherit kernel

SRCREV = "v7.0-rc7"
KBRANCH = "master"

SRC_URI = "git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git;branch=master;protocol=https"

S = "${WORKDIR}/git"

LINUX_VERSION = "7.0-rc7"
LINUX_VERSION_EXTENSION = "-mainline"
PV = "7.0+rc7"

KERNEL_FEATURES:append = " cfg/fs/vfat.scc"

COMPATIBLE_MACHINE = "qemux86-64"

FILESEXTRAPATHS:prepend := "${THISDIR}:"
SRC_URI:append = " file://dm-verity.cfg"
