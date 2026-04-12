# OpenSSH 10.3+ requires sshd-session and sshd-auth as separate binaries
# Yocto scarthgap recipe does not package them yet — create symlinks as workaround
do_install:append() {
    ln -sf /usr/sbin/sshd ${D}/usr/libexec/sshd-session
    ln -sf /usr/sbin/sshd ${D}/usr/libexec/sshd-auth
}

FILES:${PN}-sshd += "/usr/libexec/sshd-session /usr/libexec/sshd-auth"
