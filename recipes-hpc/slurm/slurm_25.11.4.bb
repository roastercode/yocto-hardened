SUMMARY = "Slurm Workload Manager"
DESCRIPTION = "Slurm — ordonnanceur de jobs HPC"
HOMEPAGE = "https://slurm.schedmd.com"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=1d61dca3f6cbd0e6c847641f8fd4c233"

SRCREV = "5d2c57980a3cf0e2e8e4bb8516f4874f3dc674cb"
SRC_URI = "git://github.com/SchedMD/slurm.git;protocol=https;nobranch=1 \
           file://slurmctld.init \
           file://slurmd.init \
           file://slurm.conf \
           file://cgroup.conf \
           file://0001-slurm-fix-all-plugins-cross-compile-undefined-symbol.patch \
           file://0002-slurm-disable-default-prep-script-plugin.patch \
           file://0003-slurm-slurmctld-export-dynamic.patch \
           file://0004-slurm-plugin-use-rtld-global.patch \
           file://0005-slurm-add-stubs-to-libslurmfull.patch"

S = "${WORKDIR}/git"

inherit autotools pkgconfig useradd

DEPENDS = "munge pmix hwloc libevent openssl zlib libyaml lz4 json-c curl"

USERADD_PACKAGES = "${PN}"
USERADD_PARAM:${PN} = "--system --home-dir /var/lib/slurm \
                        --shell /sbin/nologin \
                        --user-group slurm"

EXTRA_OECONF = " \
    --without-mysql_config \
    --disable-pam \
    --disable-sview \
    --with-munge=${STAGING_DIR_TARGET}${prefix} \
    --with-pmix=${STAGING_DIR_TARGET}${prefix} \
    --with-hwloc=${STAGING_DIR_TARGET}${prefix} \
    --disable-static \
"

INSANE_SKIP += "configure-unsafe dev-so"
RDEPENDS:${PN} += "json-c curl"
LDFLAGS:append = " -Wl,--sysroot=${STAGING_DIR_TARGET}"

do_configure() {
    cd ${B}
    oe_runconf
}

do_install:append() {
    install -d ${D}/var/lib/slurm
    install -d ${D}/etc/slurm

    install -d ${D}${sysconfdir}/init.d
    install -m 0755 ${UNPACKDIR}/slurmctld.init ${D}${sysconfdir}/init.d/slurmctld
    install -m 0755 ${UNPACKDIR}/slurmd.init    ${D}${sysconfdir}/init.d/slurmd
    install -m 0644 ${UNPACKDIR}/slurm.conf     ${D}/etc/slurm/slurm.conf
    install -m 0644 ${UNPACKDIR}/cgroup.conf   ${D}/etc/slurm/cgroup.conf
    install -m 0644 ${UNPACKDIR}/cgroup.conf   ${D}/etc/cgroup.conf

    rm -rf ${D}/run
}

FILES:${PN} += " \
    /var/lib/slurm \
    /etc/slurm \
    /etc/cgroup.conf \
    ${sysconfdir}/init.d/slurmctld \
    ${sysconfdir}/init.d/slurmd \
"

PACKAGES =+ "${PN}-slurmctld ${PN}-slurmd"
FILES:${PN}-slurmctld = "${sbindir}/slurmctld ${sysconfdir}/init.d/slurmctld"
FILES:${PN}-slurmd    = "${sbindir}/slurmd ${sysconfdir}/init.d/slurmd"

do_install:append() {
    # Supprimer les plugins Cray (non applicables sur x86/KVM)
    rm -f ${D}/usr/lib/slurm/select_cray_aries.so
    rm -f ${D}/usr/lib/slurm/core_spec_cray_aries.so
    rm -f ${D}/usr/lib/slurm/job_submit_cray_aries.so
    rm -f ${D}/usr/lib/slurm/proctrack_cray_aries.so
    rm -f ${D}/usr/lib/slurm/switch_cray_aries.so
    rm -f ${D}/usr/lib/slurm/task_cray_aries.so
    rm -f ${D}/usr/lib/slurm/node_features_knl_cray.so
    rm -f ${D}/usr/lib/slurm/power_cray_aries.so
    rm -f ${D}/usr/lib/slurm/mpi_cray_shasta.so

    # Supprimer prep_script.so : symbole send_slurmd_conf_lite
    # uniquement dans slurmd, pas exporté par libslurm — bug cross-compile
    rm -f ${D}/usr/lib/slurm/prep_script.so

    # Slurm installe les binaires avec le préfixe cross-compilateur
    # Créer des symlinks sans préfixe pour un usage normal
    for bin in slurmctld slurmd slurmdbd slurmstepd sackd; do
        if [ -f ${D}${sbindir}/${TARGET_SYS}-${bin} ]; then
            ln -sf ${TARGET_SYS}-${bin} ${D}${sbindir}/${bin}
        fi
    done
    for bin in srun sbatch squeue sinfo scancel scontrol sacct salloc; do
        if [ -f ${D}${bindir}/${TARGET_SYS}-${bin} ]; then
            ln -sf ${TARGET_SYS}-${bin} ${D}${bindir}/${bin}
        fi
    done
}

# Supprimer le plugin prep_script.so qui a un symbole indéfini
# (send_slurmd_conf_lite non résolu en cross-compilation)
do_install:append() {
}

# buildpaths in DWARF debug info and binaries — unavoidable in cross-compile
INSANE_SKIP:${PN} += "buildpaths"
INSANE_SKIP:${PN}-dbg += "buildpaths"
INSANE_SKIP:${PN}-slurmctld += "buildpaths"
INSANE_SKIP:${PN}-slurmd += "buildpaths"
INSANE_SKIP:${PN}-dev += "buildpaths"
INSANE_SKIP:${PN}-staticdev += "buildpaths"
INSANE_SKIP:${PN}-src += "buildpaths"
