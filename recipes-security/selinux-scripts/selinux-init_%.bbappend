# Remplace le script sysvinit par une version vide
# Le rootfs est pré-labelé via selinux-image.bbclass
FILESEXTRAPATHS:prepend := "${THISDIR}/selinux-init:"

SRC_URI:remove = "file://selinux-init.sh.sysvinit"
SRC_URI:append = " file://selinux-init.sh.sysvinit"
