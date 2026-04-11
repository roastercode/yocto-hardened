# Fix compilation with GCC 15 - int is now a reserved keyword in C23
# m4 1.4.19 uses 'int' as identifier in gl_list.h
CFLAGS:append = " -std=gnu17"
