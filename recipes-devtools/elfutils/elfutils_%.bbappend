# Fix GCC 15 -Werror=unterminated-string-initialization (C only, not C++)
CFLAGS:append:class-native = " -Wno-unterminated-string-initialization"
