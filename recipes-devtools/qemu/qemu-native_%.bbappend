# Fix ninja 1.13+ rejecting float -l parameter from MAKEFLAGS
PARALLEL_MAKE:class-native = "-j ${@oe.utils.cpu_count()}"

do_configure:append:class-native() {
    if [ -f ${B}/Makefile ]; then
        sed -i 's|filter -l% -j%|filter -j%|g' ${B}/Makefile
    fi
}

# Fix struct sched_attr redefinition with glibc 2.42 + GCC 15
CFLAGS:append:class-native = " -DSCHED_ATTR_DEFINED"
CXXFLAGS:append:class-native = " -DSCHED_ATTR_DEFINED"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI:append:class-native = " file://0001-qemu-fix-sched-attr-glibc-2.42.patch"
