# Fix GCC 15 C23 + Gentoo binutils 2.46 host compatibility
CFLAGS:append:class-native = " -std=gnu17 -Wno-error"
BUILD_CFLAGS:append:class-native = " -std=gnu17"
CFLAGS_FOR_BUILD:append:class-native = " -std=gnu17"

# Bypass runtime configure tests incompatible with Gentoo binutils 2.46 + GCC 15
# These are cache variables that tell configure the result without running the test
EXTRA_OECONF:append:class-native = " \
    gmp_cv_c_double_format=IEEE-little-endian \
    gmp_cv_prog_cc_works=yes \
    ac_cv_prog_cc_works=yes \
"
