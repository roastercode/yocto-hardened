# Fix GCC 15 C++23 template ADL issues with LLVM 18
CXXFLAGS:append:class-native = " -std=gnu++17"
CFLAGS:append:class-native = " -std=gnu17"
