# Fix ninja 1.12+ rejecting float -l parameter
# Remove load average limit from PARALLEL_MAKE
PARALLEL_MAKE:class-native = "-j ${@oe.utils.cpu_count()}"
