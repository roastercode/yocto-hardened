# Fix ninja 1.13+ rejecting float -l parameter from MAKEFLAGS
PARALLEL_MAKE:class-native = "-j ${@oe.utils.cpu_count()}"

python do_compile:prepend:class-native() {
    import subprocess, os
    makefile = os.path.join(d.getVar('B'), 'Makefile')
    if os.path.exists(makefile):
        subprocess.run(['sed', '-i',
            r's|$(filter -l% -j%, $(MAKEFLAGS))|$(filter -j%, $(MAKEFLAGS))|g',
            makefile], check=True)
        bb.note("Patched qemu Makefile NINJAFLAGS to remove -l parameter")
}
