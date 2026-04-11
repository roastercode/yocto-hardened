# Fix GCC 15 C23 + Gentoo binutils 2.46 host compatibility
CFLAGS:append:class-native = " -std=gnu17 -Wno-error"
BUILD_CFLAGS:append:class-native = " -std=gnu17"
CFLAGS_FOR_BUILD:append:class-native = " -std=gnu17"

python do_patch:append:class-native() {
    import subprocess, os
    configure = os.path.join(d.getVar('S'), 'configure')
    if os.path.exists(configure):
        subprocess.run(['sed', '-i',
            's/if test "$cross_compiling" = no; then/if false; then # Gentoo GCC15 compat/g',
            configure], check=True)
}
