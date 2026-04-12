# Fix GCC 15 : missing <cstdint> in multiple LLVM 18 headers (uint*_t undeclared)
# Force implicit inclusion via -include flag - backport approach from LLVM 19+
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI:append:class-native = " file://0001-llvm-fix-smallvector-cstdint-gcc15.patch"

CXXFLAGS:append:class-native = " -include cstdint"
CFLAGS:append:class-native = " -include stdint.h"
