# Fix ninja 1.13+ rejecting float -l parameter from MAKEFLAGS
PARALLEL_MAKE:class-native = "-j ${@oe.utils.cpu_count()}"

do_configure:append:class-native() {
    if [ -f ${B}/Makefile ]; then
        sed -i 's|filter -l% -j%|filter -j%|g' ${B}/Makefile
    fi
}
