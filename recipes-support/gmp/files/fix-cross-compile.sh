#!/bin/sh
sed -i 's/if test "$cross_compiling" = no; then/if false; then # Gentoo GCC15 compat/g' "$1"
