# Fix GCC 15 : missing <cstdint> in SmallVector.h (uint64_t undeclared)
# Backport from LLVM 19+
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI:append:class-native = " file://0001-llvm-fix-smallvector-cstdint-gcc15.patch"
