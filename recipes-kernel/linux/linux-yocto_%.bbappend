# FTRFS arm64 — integrity and FEC kernel config
FILESEXTRAPATHS:prepend := "${THISDIR}:"

SRC_URI:append:qemuarm64 = " file://ftrfs-arm64.cfg"

COMPATIBLE_MACHINE:append = "|qemuarm64"
