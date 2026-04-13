require recipes-core/images/core-image-minimal.bb

IMAGE_INSTALL += "openssh"

inherit extrausers
EXTRA_USERS_PARAMS = "usermod -p '' root;"
