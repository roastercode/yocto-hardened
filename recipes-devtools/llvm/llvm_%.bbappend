# Fix GCC 15 : missing <cstdint> in multiple LLVM 18 headers (uint*_t undeclared)
# -include cstdint ONLY for C++ (not C, not .S assembler files)
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI:append:class-native = " file://0001-llvm-fix-smallvector-cstdint-gcc15.patch"

CXXFLAGS:append:class-native = " -include cstdint"
