SUMMARY = "Event notification library"
DESCRIPTION = "libevent — dépendance de munge et slurm"
HOMEPAGE = "https://libevent.org"
LICENSE = "BSD-3-Clause"
LIC_FILES_CHKSUM = "file://LICENSE;md5=17f20574c0b154d12236d5fbe964f549"

SRC_URI = "https://github.com/libevent/libevent/releases/download/release-${PV}-stable/libevent-${PV}-stable.tar.gz"
SRC_URI[sha256sum] = "92e6de1be9ec176428fd2367677e61ceffc2ee1cb119035037a27d346b0403bb"

S = "${WORKDIR}/libevent-${PV}-stable"

inherit autotools pkgconfig

PACKAGECONFIG ??= "openssl"
PACKAGECONFIG[openssl] = "--enable-openssl,--disable-openssl,openssl"

EXTRA_OECONF = "--disable-static --disable-samples"

do_compile:prepend() {
    mkdir -p ${B}/test
}
