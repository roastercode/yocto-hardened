# Fix GCC 15 C23 + Gentoo binutils 2.46 host compatibility
CFLAGS:append:class-native = " -std=gnu17 -Wno-error"
BUILD_CFLAGS:append:class-native = " -std=gnu17"
CFLAGS_FOR_BUILD:append:class-native = " -std=gnu17"

# Force cross_compiling=yes to skip runtime tests
# gmp checks "if test $cross_compiling = no" before running binary tests
EXTRA_OECONF:append:class-native = " cross_compiling=yes"
