# Fix GCC 15 -Werror=unterminated-string-initialization
CFLAGS:append:class-native = " -Wno-unterminated-string-initialization"
CXXFLAGS:append:class-native = " -Wno-unterminated-string-initialization"
