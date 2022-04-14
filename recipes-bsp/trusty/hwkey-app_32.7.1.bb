TEGRA_SRC_SUBARCHIVE = "Linux_for_Tegra/source/public/trusty_src.tbz2"
require recipes-bsp/tegra-sources/tegra-sources-32.7.1.inc

SUMMARY:forcevariable = "Sample client application to communicate with the hwkey-agent TA"
DESCRIPTION:forcevariable = "Sample Client Application (CA) to communicate with the \
hwkey-agent Trusted Application (TA)"
LICENSE:forcevariable = "MIT"
LIC_FILES_CHKSUM:forcevariable = "file://LICENSE;md5=0f2184456a07e1ba42a53d9220768479"

require recipes-bsp/trusty/trusty-l4t.inc

S = "${WORKDIR}/trusty/app/nvidia-sample/hwkey-agent/CA_sample/"

export CROSS_COMPILER="${STAGING_DIR_NATIVE}/gcc-linaro-baremetal-arm/bin/arm-eabi-"

do_compile() {
    oe_runmake -C ${S}
}

do_install() {
    install -d ${D}${sbindir}
    install ${S}/out/${BPN} ${D}${sbindir}/
}
