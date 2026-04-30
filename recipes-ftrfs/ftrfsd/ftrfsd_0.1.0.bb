# SPDX-License-Identifier: MIT
#
# ftrfsd_0.1.0.bb — FTRFS Radiation Event Journal daemon
#
# Userspace daemon that reads the RAF ring buffer from a FTRFS superblock
# and logs RS correction events to syslog.
#
# Depends on: ftrfs-module (kernel module must be loaded before ftrfsd starts)

SUMMARY = "FTRFS Radiation Event Journal daemon"
DESCRIPTION = "Reads the RAF ring buffer from a FTRFS superblock and logs \
RS correction events to syslog. First brique of the semantic-sync \
trust substrate: verifiable per-node event attestation."
LICENSE = "GPL-2.0-only"
PR = "r2"
LIC_FILES_CHKSUM = "file://ftrfsd.c;beginline=1;endline=2;md5=657d74fcbced6c83d92fc8b579438888"

DEPENDS = "openssl"

SRC_URI = "file://ftrfsd-0.1.0/"
S = "${WORKDIR}/ftrfsd-0.1.0"

do_compile() {
    ${CC} ${CFLAGS} ${LDFLAGS} -o ftrfsd ftrfsd.c -lcrypto
    ${CC} ${CFLAGS} ${LDFLAGS} -o inject_raf inject_raf.c
}

do_install() {
    install -d ${D}${sbindir}
    install -m 0755 ftrfsd ${D}${sbindir}/ftrfsd
    install -m 0755 inject_raf ${D}${sbindir}/inject_raf
}
