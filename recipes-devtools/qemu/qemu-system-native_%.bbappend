# Fix ninja 1.13+ rejecting float -l parameter from MAKEFLAGS
PARALLEL_MAKE = "-j ${@oe.utils.cpu_count()}"

do_compile:prepend() {
    if [ -f ${B}/Makefile ]; then
        sed -i 's|filter -l% -j%|filter -j%|g' ${B}/Makefile
    fi
}
