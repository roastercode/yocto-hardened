CFLAGS:append:class-native = " -std=gnu17"
CXXFLAGS:append:class-native = " -std=gnu++17"
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI:append:class-native = " file://0001-cmake-fix-cstdint-gcc15.patch"
