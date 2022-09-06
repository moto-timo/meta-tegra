SUMMARY = "OP-TEE luks-srv sample app"
DESCRIPTION = "The luks-srv-app is a sample CA program that can be used to \
query the hardware-based passphrase from the TA. Then the third party OSS \
LUKS utility e.g. "cryptsetup" can use the passphrase to unlock the encrypted \
disks during the boot process. Once the boot process is done, the CA can send \
LUKS_SRV_TA_CMD_SRV_DOWN command to TA. This command tells the luks-srv TA \
not to respond to any LUKS_GET passphrase command again until reboot. This \
allows the passphrase to be extracted during boot (e.g. in initrd) but then \
prevents any form of later attack/malicious-code that attempts to obtain the \
passphrase again."
HOMEPAGE = "https://www.op-tee.org/"

LICENSE = "BSD-2-Clause"
LIC_FILES_CHKSUM = "file://LICENSE;md5=6938d70d5e5d49d31049419e85bb82f8"

inherit l4t_bsp python3native
require optee-tegra.inc

DEPENDS = "python3-cryptography-native optee-os-tadevkit-tegra optee-client-tegra"

S = "${WORKDIR}/optee/samples/luks-srv"
B = "${WORKDIR}/build"
PV = "${L4T_VERSION}"

EXTRA_OEMAKE += " \
    CFLAGS32='--sysroot=${STAGING_DIR_HOST}' \
    CFLAGS64='--sysroot=${STAGING_DIR_HOST}' \
    CROSS_COMPILE='${HOST_PREFIX}' \
    PYTHON3='${PYTHON}' \
    TA_DEV_KIT_DIR='${TA_DEV_KIT_DIR}' \
    OPTEE_CLIENT_EXPORT="${D}/usr" \
    O='${B}' \
"

do_compile() {
    oe_runmake -C ${S} all
}
do_compile[cleandirs] = "${B}"

do_install() {
    install -d ${D}${sbindir}
    install -m 0755 ${B}/ca/luks-srv/luks-srv-app ${D}${sbindir}

    install -d ${D}${nonarch_base_libdir}/optee_armtz
    install -m 0644 ${B}/early_ta/luks-srv/b83d14a8-7128-49df-9624-35f14f65ca6c.ta ${D}${nonarch_base_libdir}/optee_armtz

    install -d ${D}${includedir}/optee/early_ta/luks-srv
    install -m 0755 ${B}/early_ta/luks-srv/b83d14a8-7128-49df-9624-35f14f65ca6c.stripped.elf ${D}${includedir}/optee/early_ta/luks-srv
}

FILES:${PN} += "${nonarch_base_libdir}/optee_armtz"
FILES:${PN}-dev = "${includedir}/optee/"
INSANE_SKIP:${PN} = "ldflags already-stripped"

PACKAGE_ARCH = "${SOC_FAMILY_PKGARCH}"
