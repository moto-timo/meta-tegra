# image_type_bootpart.bbclass
#
# Copyright (c) 2020-2021, NVIDIA CORPORATION. All rights reserved.
# Copyright (c) 2022, Konsulko Group
# SPDX-License-Identifier: BSD-3-Clause
#
# Inspired by disk_encryption_helper.func and flash.sh from L4T 32.7.1
#
# Portions borrowed from image_types.bbclass
#

inherit image_types

IMAGE_TYPES += "bootpart"

fstype ?= "ext4"

IMAGE_CMD_bootpart () {
	ROOTFS_BOOTPART_SIZE=163600000000
        # Create initial disk image
        
        # If generating an empty image the size of the sparse block should be large
        # enough to allocate an ext4 filesystem using 4096 bytes per inode, this is
        # about 60K, so dd needs a minimum count of 60, with bs=1024 (bytes per IO)
        eval local COUNT=\"0\"
        eval local MIN_COUNT=\"60\"
        if [ $ROOTFS_BOOTPART_SIZE -lt $MIN_COUNT ]; then
                eval COUNT=\"$MIN_COUNT\"
        fi
        # Create a sparse image block
        rootfs_bootpart_file="${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.bootpart.${fstype}"
        bbdebug 1 Executing "dd if=/dev/zero of=${rootfs_bootpart_file} seek=$ROOTFS_BOOTPART_SIZE count=$COUNT bs=1024"
        dd if=/dev/zero of=${rootfs_bootpart_file} seek=${ROOTFS_BOOTPART_SIZE} count=$COUNT bs=1024
        bbdebug 1 "Actual Rootfs size:  `du -s ${IMAGE_ROOTFS}/boot/`"
        bbdebug 1 "Actual Partion size: `stat -c '%s' ${rootfs_bootpart_file}`"
	bbdebug 1 Executing "mkfs.${fstype} -F $extra_imagecmd ${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.bootpart.$fstype -d ${IMAGE_ROOTFS}/boot"
	mkfs.${fstype} -F $extra_imagecmd ${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.bootpart.${fstype} -d ${IMAGE_ROOTFS}/boot
	# Error codes 0-3 indicate successfull operation of fsck (no errors or errors corrected)
	fsck.${fstype} -pvfD ${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.bootpart.${fstype} || [ $? -le 3 ]

	bbdebug 1 "Converting RAW image to Sparse image... "
	mv -f "${rootfs_bootpart_file}" "${rootfs_bootpart_file}.raw"
	mksparse --fillpattern=0 ${rootfs_bootpart_file}.raw ${rootfs_bootpart_file} ||
	bbfatal "Failed to convert raw image to sparse image."
        bbdebug 1 "Successfully built ${rootfs_bootpart_file}. "
}

do_image_bootpart[depends] += "tegra-bootfiles:do_populate_sysroot tegra-bootfiles:do_populate_lic \
                                 tegra-redundant-boot-rollback:do_populate_sysroot virtual/kernel:do_deploy \
                                 ${@'${INITRD_IMAGE}:do_image_complete' if d.getVar('INITRD_IMAGE') != '' else  ''} \
                                 ${@'${IMAGE_UBOOT}:do_deploy ${IMAGE_UBOOT}:do_populate_lic' if d.getVar('IMAGE_UBOOT') != '' else  ''} \
                                 cboot:do_deploy virtual/secure-os:do_deploy virtual/bootlogo:do_deploy ${TEGRA_SIGNING_EXTRA_DEPS}"
