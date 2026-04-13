SUMMARY = "FTRFS userspace formatter"
DESCRIPTION = "mkfs.ftrfs — format a block device as FTRFS"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=4c9369db79a4345d581e1a2b9b732941"

SRC_URI = "file://ftrfs-0.1.0/"
S = "${WORKDIR}/ftrfs-0.1.0"

do_compile() {
    ${CC} ${CFLAGS} ${LDFLAGS} -o mkfs.ftrfs mkfs.ftrfs.c
}

do_install() {
    install -d ${D}${sbindir}
    install -m 0755 mkfs.ftrfs ${D}${sbindir}/mkfs.ftrfs
}
