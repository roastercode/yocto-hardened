# Fix GCC 15 C23 + Gentoo binutils 2.46 host compatibility
CFLAGS:append:class-native = " -std=gnu17 -Wno-error"
BUILD_CFLAGS:append:class-native = " -std=gnu17"
CFLAGS_FOR_BUILD:append:class-native = " -std=gnu17"

# gmp configure uses its own gcc invocation ignoring CFLAGS
# Force std=gnu17 via PATH wrapper
PATH:prepend:class-native = "${HOME}/yocto/gmp-gcc-wrapper:"
