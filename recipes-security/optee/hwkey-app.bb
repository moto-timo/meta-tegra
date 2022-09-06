SUMMARY = "OP-TEE hwkey-agent sample app"
DESCRIPTION = "The CA sample program named 'hwkey-app' that is intended to \
work with the 'hwkey-agent' TA to provide encryption and decryption function \
with the keys provided by TA. \
\
Using the user-defined key in EKB: \
The CA must use the TEE Client API to communicate with the TA and send \
the request with payload to TA to perform the crypto operation. Once \
TA receives the request, it processes the data and uses the crypto \
library to perform the operations with the user-defined key. This is a \
software-based crypto operation provided by TA. \
\
Hardware-based RNG (Random Number Generator): \
The CA can be used to query random numbers from the TA. The TA handles \
the HW RNG to extract random numbers and return them to the CA."
HOMEPAGE = "https://www.op-tee.org/"

LICENSE = "BSD-2-Clause"
LIC_FILES_CHKSUM = "file://LICENSE;md5=6938d70d5e5d49d31049419e85bb82f8"

inherit l4t_bsp python3native
require optee-tegra.inc

DEPENDS = "python3-cryptography-native optee-os-tadevkit-tegra optee-client-tegra"

S = "${WORKDIR}/optee/samples/hwkey-agent"
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
    install -m 0755 ${B}/ca/hwkey-agent/hwkey-app ${D}${sbindir}

    install -d ${D}${nonarch_base_libdir}/optee_armtz
    install -m 0644 ${B}/ta/hwkey-agent/82154947-c1bc-4bdf-b89d-04f93c0ea97c.ta ${D}${nonarch_base_libdir}/optee_armtz
}

FILES:${PN} += "${nonarch_base_libdir}/optee_armtz"
FILES:${PN}-dev = "${includedir}/optee/"
INSANE_SKIP:${PN} = "ldflags already-stripped"

PACKAGE_ARCH = "${SOC_FAMILY_PKGARCH}"
