DESCRIPTION = "Minimal initramfs init script with LUKS disk encryption support"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "\
    file://init-crypt-boot.sh \
    file://platform-preboot.sh \
    ${@'file://platform-preboot-cboot.sh' if d.getVar('PREFERRED_PROVIDER_virtual/bootloader').startswith('cboot') else ''} \
    ${@bb.utils.contains('MACHINEOVERRIDES', 'cryptparts', 'file://platform-pre-switchroot.sh', '', d)} \
"

COMPATIBLE_MACHINE = "(tegra)"

S = "${WORKDIR}"

do_install() {
    install -m 0755 ${WORKDIR}/init-crypt-boot.sh ${D}/init
    install -m 0555 -d ${D}/proc ${D}/sys
    install -m 0755 -d ${D}/dev ${D}/mnt ${D}/run ${D}/usr
    install -m 1777 -d ${D}/tmp
    mknod -m 622 ${D}/dev/console c 5 1
    install -d ${D}${sysconfdir}
    if [ -e ${WORKDIR}/platform-preboot-cboot.sh ]; then
        cat ${WORKDIR}/platform-preboot-cboot.sh ${WORKDIR}/platform-preboot.sh > ${WORKDIR}/platform-preboot.tmp
        install -m 0644 ${WORKDIR}/platform-preboot.tmp ${D}${sysconfdir}/platform-preboot
        rm ${WORKDIR}/platform-preboot.tmp
    else
        install -m 0644 ${WORKDIR}/platform-preboot.sh ${D}${sysconfdir}/platform-preboot
    fi
    if [ -e ${WORKDIR}/platform-pre-switchroot.sh ]; then
        install -m 0644 ${WORKDIR}/platform-pre-switchroot.sh ${D}${sysconfdir}/platform-pre-switchroot
    fi
}

RDEPENDS_${PN} = "\
    ${@'util-linux-blkid' if d.getVar('PREFERRED_PROVIDER_virtual/bootloader').startswith('cboot') else ''} \
    ${@bb.utils.contains('MACHINEOVVERIDES', 'cryptparts', 'luks-srv-app cryptsetup', '', d)} \
"
FILES_${PN} = "/"
