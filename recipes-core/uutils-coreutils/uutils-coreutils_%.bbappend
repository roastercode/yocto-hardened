# Désactiver le support SELinux dans uutils-coreutils
# clang-native n'est pas disponible dans ce layer
# Le SELinux est géré par refpolicy séparément
PACKAGECONFIG:remove = "selinux"
