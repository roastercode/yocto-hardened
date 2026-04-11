# Fix GCC 15 + Gentoo binutils 2.46 host compatibility
CFLAGS:append:class-native = " -std=gnu17"
BUILD_CFLAGS:append:class-native = " -std=gnu17"
CFLAGS_FOR_BUILD:append:class-native = " -std=gnu17"

do_configure:prepend:class-native() {
    # Skip long long runtime tests that fail with Gentoo binutils 2.46 + GCC 15
    sed -i 's/if test "\$cross_compiling" = no; then/if false; then # Gentoo GCC15 compat/g' \
        ${S}/configure
}
