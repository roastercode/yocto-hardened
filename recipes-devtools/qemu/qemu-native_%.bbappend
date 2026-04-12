# Fix ninja 1.13+ rejecting float -l parameter from MAKEFLAGS
PARALLEL_MAKE:class-native = "-j ${@oe.utils.cpu_count()}"

# Override NINJAFLAGS to strip -l parameter passed by make
do_compile:prepend:class-native() {
    export NINJAFLAGS="-j ${@oe.utils.cpu_count()} -d keepdepfile"
}
