# Fix GCC 15 C23 implicit function declarations
CFLAGS:append = " -std=gnu17"
BUILD_CFLAGS:append = " -std=gnu17"
CFLAGS_FOR_BUILD:append = " -std=gnu17"
EXTRA_OECONF:append = " CC_FOR_BUILD='gcc -std=gnu17'"
