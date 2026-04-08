SUMMARY = "MUNGE authentication service"
DESCRIPTION = "MUNGE — service d'authentification pour Slurm"
HOMEPAGE = "https://dun.github.io/munge/"
LICENSE = "GPL-3.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=d32239bcb673463ab874e80d47fae504"

SRC_URI = "https://github.com/dun/munge/releases/download/munge-${PV}/munge-${PV}.tar.xz \
           file://munge.init \
           file://0001-munge-cross-compile-fifo-test.patch \
           file://0002-munge-select-auth-cross-compile.patch"
SRC_URI[sha256sum] = "3f979df117a34c74db8fe2835521044bdeb08e3b7d0f168ca97c3547f51da9ba"

inherit autotools pkgconfig useradd

DEPENDS = "libevent openssl zlib libgcrypt"

USERADD_PACKAGES = "${PN}"
USERADD_PARAM:${PN} = "--system --home-dir /var/lib/munge \
                        --shell /sbin/nologin \
                        --user-group munge"

EXTRA_OECONF = " \
    --with-crypto-lib=openssl \
    --localstatedir=/var \
    --runstatedir=/run \
"

LDFLAGS:append = " -Wl,--sysroot=${STAGING_DIR_TARGET}"
INSANE_SKIP += "configure-unsafe"
INSANE_SKIP:${PN} += "host-user-contaminated"

do_install:append() {
    # Supprimer les répertoires runtime — créés par le init script
    rm -rf ${D}/var/log
    rm -rf ${D}/var/volatile
    rm -rf ${D}/run

    # Garder uniquement /var/lib/munge et /etc/munge
    install -d ${D}/var/lib/munge
    install -d ${D}/etc/munge
    chmod 0700 ${D}/var/lib/munge
    chmod 0700 ${D}/etc/munge

    # Script init SysVinit
    install -d ${D}${sysconfdir}/init.d
    install -m 0755 ${WORKDIR}/munge.init ${D}${sysconfdir}/init.d/munge
}

FILES:${PN} += " \
    /var/lib/munge \
    /etc/munge \
    ${sysconfdir}/init.d/munge \
    ${sysconfdir}/default \
    ${sysconfdir}/logrotate.d \
"
