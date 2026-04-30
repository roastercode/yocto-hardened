SUMMARY = "Image custom minimale avec nos outils"
LICENSE = "MIT"

# Nécessaire pour que 'runqemu qemux86-64 custom-image' fonctionne
IMAGE_LINK_NAME = "custom-image-${MACHINE}"

# packagegroup-core-boot = kernel + init + busybox (le minimum pour booter)
# ${CORE_IMAGE_EXTRA_INSTALL} = hook pour ajouter des paquets depuis local.conf
# hello-custom = notre recette custom
IMAGE_INSTALL = "packagegroup-core-boot ${CORE_IMAGE_EXTRA_INSTALL} hello-custom packagegroup-selinux-minimal"

IMAGE_LINGUAS = " "

inherit core-image dm-verity-image selinux-image

# Taille max du rootfs en KB (50MB)
IMAGE_ROOTFS_SIZE ?= "51200"
IMAGE_ROOTFS_EXTRA_SPACE:append = "${@bb.utils.contains("DISTRO_FEATURES", "systemd", " + 4096", "", d)}"

# Hardening D2 : pas de debug-tweaks
IMAGE_FEATURES:remove = "debug-tweaks"
IMAGE_FEATURES += "read-only-rootfs"

# Mot de passe root obligatoire sans debug-tweaks
# Credentials séparés — ne pas versionner credentials.inc
require credentials.inc

# Option B : ext4 + dm-verity + SELinux enforcing
# ext4 supporte les xattrs → SELinux peut enforcer les labels
IMAGE_FSTYPES = "ext4"
VERITY_IMAGE_TYPE = "ext4"
QB_DEFAULT_FSTYPE = "ext4"

# overlayfs-etc : /etc writable en RAM
IMAGE_FEATURES += "overlayfs-etc"
OVERLAYFS_ETC_MOUNT_POINT = "/data"
OVERLAYFS_ETC_DEVICE = "tmpfs"
OVERLAYFS_ETC_FSTYPE = "tmpfs"

# Créer le point de montage /data dans l'image
ROOTFS_POSTPROCESS_COMMAND:append = " create_overlayfs_mountpoint;"
create_overlayfs_mountpoint() {
    mkdir -p ${IMAGE_ROOTFS}/data
}

# Crée file_contexts.local pour labelliser busybox comme init_exec_t
ROOTFS_POSTPROCESS_COMMAND:append = " install_selinux_fc_local;"
install_selinux_fc_local() {
    FC_DIR="${IMAGE_ROOTFS}/etc/selinux/targeted/contexts/files"
    if [ -d "${FC_DIR}" ]; then
	printf '/bin/busybox\tsystem_u:object_r:init_exec_t:s0\n' >> "${FC_DIR}/file_contexts.local"
	printf '/sbin/init\tsystem_u:object_r:init_exec_t:s0\n' >> "${FC_DIR}/file_contexts.local"
    fi
}

# Override selinux_set_labels pour inclure file_contexts.local
selinux_set_labels() {
    if [ -f ${IMAGE_ROOTFS}/${sysconfdir}/selinux/config ]; then
     POL_TYPE=$(sed -n -e "s&^SELINUXTYPE[[:space:]]*=[[:space:]]*\([0-9A-Za-z_]\+\)&\1&p" \
	  ${IMAGE_ROOTFS}/${sysconfdir}/selinux/config)
     SEL_FC="${IMAGE_ROOTFS}/${sysconfdir}/selinux/${POL_TYPE}/contexts/files/file_contexts"
     SEL_FC_LOCAL="${IMAGE_ROOTFS}/${sysconfdir}/selinux/${POL_TYPE}/contexts/files/file_contexts.local"
     SEL_POLICY=$(ls ${IMAGE_ROOTFS}/${sysconfdir}/selinux/${POL_TYPE}/policy/policy.* 2>/dev/null | sort -V | tail -1)
     SEL_FC_ARGS="${SEL_FC}"
     [ -f "${SEL_FC_LOCAL}" ] && SEL_FC_ARGS="${SEL_FC} ${SEL_FC_LOCAL}"
     if ! setfiles -m -r ${IMAGE_ROOTFS} -c ${SEL_POLICY} ${SEL_FC_ARGS} ${IMAGE_ROOTFS}
     then
	   bbwarn "Failed to set security contexts. Restoring security contexts will run on first boot."
	   echo "# first boot relabelling" > ${IMAGE_ROOTFS}/.autorelabel
     fi
    fi
}

# Pré-labéliser le rootfs au build time → pas de relabeling au 1er boot
FIRST_BOOT_RELABEL = "0"
