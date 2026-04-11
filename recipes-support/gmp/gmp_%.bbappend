# Fix GCC 15 C23 + Gentoo binutils 2.46 host compatibility
CFLAGS:append:class-native = " -std=gnu17 -Wno-error"
BUILD_CFLAGS:append:class-native = " -std=gnu17"
CFLAGS_FOR_BUILD:append:class-native = " -std=gnu17"

do_patch:append:class-native() {
    sed -i 's/if test "$cross_compiling" = no; then/if false; then # Gentoo GCC15 compat/g' \
        ${S}/configure
}
