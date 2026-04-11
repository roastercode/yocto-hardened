# Fix GCC 15 C23 + Gentoo binutils 2.46 host compatibility
CFLAGS:append:class-native = " -std=gnu17 -Wno-error"
BUILD_CFLAGS:append:class-native = " -std=gnu17"
CFLAGS_FOR_BUILD:append:class-native = " -std=gnu17"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

do_patch:append:class-native() {
    ${WORKDIR}/fix-cross-compile.sh ${S}/configure
}
