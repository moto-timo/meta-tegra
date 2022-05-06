require recipes-core/images/tegra-minimal-initramfs.bb
DESCRIPTION:forcevariable = "Minimal initramfs image for Tegra platforms with LUKS encryption"

PACKAGE_INSTALL:remove = "tegra-minimal-init"
PACKAGE_INSTALL:append = " tegra-crypt-init util-linux-mount"
