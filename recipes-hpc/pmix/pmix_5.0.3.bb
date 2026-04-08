SUMMARY = "Process Management Interface for HPC"
DESCRIPTION = "PMIx — interface de gestion de processus pour Slurm"
HOMEPAGE = "https://pmix.org"
LICENSE = "BSD-3-Clause"
LIC_FILES_CHKSUM = "file://LICENSE;md5=5f7c7fac9e43225b46f4050e0f253133"

SRC_URI = "https://github.com/openpmix/openpmix/releases/download/v${PV}/pmix-${PV}.tar.bz2"
SRC_URI[sha256sum] = "474ebf5bbc420de442ab93f1b61542190ac3d39ca3b0528a19f586cf3f1cbd94"

inherit autotools pkgconfig

DEPENDS = "libevent openssl zlib hwloc"

EXTRA_OECONF = " \
    --with-libevent=${STAGING_DIR_TARGET}${prefix} \
    --with-hwloc=${STAGING_DIR_TARGET}${prefix} \
    --disable-static \
    --disable-per-user-config-files \
"

