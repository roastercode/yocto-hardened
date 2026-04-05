# dm-verity-image.bbclass
# Génère un hash tree dm-verity pour le rootfs ext4
# Usage : inherit dm-verity-image dans une recette image

VERITY_IMAGE_TYPE ?= "squashfs"
VERITY_HASH_FILE ?= "${IMGDEPLOYDIR}/${IMAGE_NAME}.verity-roothash"

python do_image_verity() {
    import subprocess, os

    deploy_dir = d.getVar('IMGDEPLOYDIR')
    image_name = d.getVar('IMAGE_NAME')
    image_link = d.getVar('IMAGE_LINK_NAME')
    fstype = d.getVar('VERITY_IMAGE_TYPE')
    hash_file = d.getVar('VERITY_HASH_FILE')

    rootfs = os.path.join(deploy_dir, f"{image_name}.{fstype}")
    hash_img = os.path.join(deploy_dir, f"{image_name}.verity.hash")

    if not os.path.exists(rootfs):
          bb.fatal(f"Rootfs not found: {rootfs}")

    bb.note(f"Running veritysetup on {rootfs}")

    result = subprocess.run(
          ["veritysetup", "format", rootfs, hash_img],
          capture_output=True, text=True
    )

    if result.returncode != 0:
          bb.fatal(f"veritysetup failed: {result.stderr}")

    # Extraire le root hash depuis la sortie
    root_hash = ""
    for line in result.stdout.splitlines():
          if "Root hash:" in line:
              root_hash = line.split()[-1]
              break

    if not root_hash:
          bb.fatal("Could not extract root hash from veritysetup output")

    # Sauvegarder le root hash
    with open(hash_file, 'w') as f:
          f.write(f"ROOT_HASH={root_hash}\n")
          f.write(f"HASH_IMAGE={hash_img}\n")
          f.write(f"ROOTFS={rootfs}\n")

    bb.note(f"dm-verity root hash: {root_hash}")
    bb.note(f"Root hash saved to: {hash_file}")

    # Créer un lien symbolique sans timestamp
    link = os.path.join(deploy_dir, f"{image_link}.verity-roothash")
    if os.path.exists(link):
          os.remove(link)
    os.symlink(os.path.basename(hash_file), link)
}

addtask do_image_verity after do_image_complete before do_build
do_image_verity[depends] += "cryptsetup-native:do_populate_sysroot"
