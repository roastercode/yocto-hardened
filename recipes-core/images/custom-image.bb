SUMMARY = "Image custom minimale avec nos outils"
LICENSE = "MIT"

# Nécessaire pour que 'runqemu qemux86-64 custom-image' fonctionne
IMAGE_LINK_NAME = "custom-image-${MACHINE}"

# packagegroup-core-boot = kernel + init + busybox (le minimum pour booter)
# ${CORE_IMAGE_EXTRA_INSTALL} = hook pour ajouter des paquets depuis local.conf
# hello-custom = notre recette custom
IMAGE_INSTALL = "packagegroup-core-boot ${CORE_IMAGE_EXTRA_INSTALL} hello-custom packagegroup-selinux-minimal"

IMAGE_LINGUAS = " "

inherit core-image

# Taille max du rootfs en KB (50MB)
#IMAGE_ROOTFS_SIZE ?= "51200"
IMAGE_ROOTFS_EXTRA_SPACE:append = "${@bb.utils.contains("DISTRO_FEATURES", "systemd", " + 4096", "", d)}"

# Système de fichier embarqué
IMAGE_FSTYPES = "squashfs"
QB_DEFAULT_FSTYPE = "squashfs"

# Hardening D2 : pas de debug-tweaks
IMAGE_FEATURES:remove = "debug-tweaks"
IMAGE_FEATURES += "read-only-rootfs overlayfs-etc"
OVERLAYFS_ETC_MOUNT_POINT = "/data"
OVERLAYFS_ETC_DEVICE = "tmpfs"
OVERLAYFS_ETC_FSTYPE = "tmpfs"

# Mot de passe root obligatoire sans debug-tweaks
# Credentials séparés — ne pas versionner credentials.inc
require credentials.inc

# D8 : dm-verity hash tree generation
inherit dm-verity-image

# Créer le point de montage /data dans le squashfs
ROOTFS_POSTPROCESS_COMMAND:append = " create_overlayfs_mountpoint;"
create_overlayfs_mountpoint() {
    mkdir -p ${IMAGE_ROOTFS}/data
}
