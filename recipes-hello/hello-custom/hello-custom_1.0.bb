DESCRIPTION = "Hello World depuis notre layer custom"
SECTION = "examples"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# Source locale — BitBake cherche dans le sous-dossier files/ de la recette
SRC_URI = "file://hello-custom.c"

# Le .c est copié directement dans WORKDIR (pas d'archive à extraire)
S = "${WORKDIR}/${BP}"

do_compile() {
    ${CC} ${CFLAGS} ${LDFLAGS} hello-custom.c -o hello-custom
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 hello-custom ${D}${bindir}
}
