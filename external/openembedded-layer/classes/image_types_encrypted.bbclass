# image_type_encrypted.bbclass
#
# Copyright (c) 2020-2021, NVIDIA CORPORATION. All rights reserved.
# Copyright (c) 2022, Konsulko Group
# SPDX-License-Identifier: BSD-3-Clause
#
# Inspired by disk_encryption_helper.func and flash.sh from L4T 32.7.1
#
# Portions borrowed from image_types.bbclass

inherit image_types

DEPENDS:append = " cryptsetup-native util-linux-native"

IMAGE_TYPES += "encrypted"

UNENCRYPTED_BOOT_PART ?= "1"
GEN_LUKS_PASSPHRASE_ARGS ?= "--context-string ${CRYPTSETUP_FSUUID} --generic-pass"
#GEN_LUKS_PASSPHRASE_ARGS ?= "--context-string ${CRYPTSETUP_FSUUID} --unique-pass --key-file ${USER_KEY_FOR_EKS} --ecid ${ECID}"
GEN_LUKS_PASSPHRASE_CMD ?= "$(oe-run-native gen-luks-passphrase gen-luks-passphrase.py ${GEN_LUKS_PASSPHRASE_ARGS})"
CRYPTSETUP_BIN ?= "$(oe-run-native cryptsetup cryptsetup)"
CRYPTSETUP_DEVICE_TYPE ?= "luks1"
CRYPTSETUP_CIPHER ?= "aes-cbc-essiv:sha256"
CRYPTSETUP_FSUUID ?= "$(oe-run-native  util-linux-libuuid uuidgen)"
CRYPTSETUP_KEY_SIZE ?= "128"
fstype ?= "ext4"

IMAGE_CMD_encrypted () {
        # Create initial disk image
        
        # If generating an empty image the size of the sparse block should be large
        # enough to allocate an ext4 filesystem using 4096 bytes per inode, this is
        # about 60K, so dd needs a minimum count of 60, with bs=1024 (bytes per IO)
        eval local COUNT=\"0\"
        eval local MIN_COUNT=\"60\"
        if [ $ROOTFS_SIZE -lt $MIN_COUNT ]; then
                eval COUNT=\"$MIN_COUNT\"
        fi
        # Create a sparse image block
        encrypted_rootfs_file="${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.${fstype}.encrypted"
        bbdebug 1 Executing "dd if=/dev/zero of=${encrypted_rootfs_file} seek=$ROOTFS_SIZE count=$COUNT bs=1024"
        dd if=/dev/zero of=${encrypted_rootfs_file} seek=$ROOTFS_SIZE count=$COUNT bs=1024
        bbdebug 1 "Actual Rootfs size:  `du -s ${IMAGE_ROOTFS}`"
        bbdebug 1 "Actual Partion size: `stat -c '%s' ${encrypted_rootfs_file}`"

        # Create loopback device
	bbdebug 1 Executing "losetup --show -f '${encrypted_rootfs_file}'"
        loop_dev="$(losetup --show -f "${encrypted_rootfs_file}")"

        local encrypted_root_dm="tegra_encrypted_root"
        local encrypted_root_dm_dev="/dev/mapper/${encrypted_root_dm}"

        # Add the LUKS header.
        eval ${GEN_LUKS_PASSPHRASE_CMD} | ${CRYPTSETUP_BIN} \
                --type ${CRYPTSETUP_DEVICE_TYPE} \
                --cipher ${CRYPTSETUP_CIPHER} \
                --key-size ${CRYPTSETUP_KEY_SIZE} \
                --uuid "${CRYPTSETUP_FSUUID}" \
                luksFormat \
                ${loop_dev} ||
        bbfatal "Adding LUKS header to ${encrypted_rootfs_file} failed."

        # Unlock the encrypted filesystem image.
        if [ -e "${encrypted_root_dm_dev}" ]; then
                umount ${encrypted_root_dm_dev}
                ${CRYPTSETUP_BIN} luksClose ${encrypted_root_dm}
        fi
        eval ${GEN_LUKS_PASS_CMD} | ${CRYPTSETUP_BIN} \
                luksOpen ${loop_dev} ${encrypted_root_dm} ||
        bbfatal "Unlocking ${encrypted_rootfs_file} failed."

        bbdebug 1 Executing "mkfs.$fstype -F $extra_imagecmd ${encrypted_root_dm_dev}"
        mkfs.$fstype -F $extra_imagecmd ${encrypted_root_dm_dev} > /dev/null 2>&1 ||
        bbfatal "Formating ${fstype} filesystem on ${encrypted_root_dm_dev} failed."
        mkdir -p mnt ||
        bbfatal "Making ${encrypted_rootfs_file} mount point failed."
        mount ${encrypted_root_dm_dev} mnt ||
        bbfatal "Mounting ${encrypted_rootfs_file} failed."

        # Processing partition data.
        if [ "${IMAGE_ROOTFS}" != "" ]; then
                pushd mnt > /dev/null 2>&1
                bbdebug 1 "Populating filesystem from ${IMAGE_ROOTFS} ... "
                if [ "${UNENCRYPTED_BOOT_PART}" == "1" ]; then
                        (cd ${IMAGE_ROOTFS}; tar -cf --exclude /boot - *) | tar xf - ||
			bbfatal "Failed to populate file system -- excluding /boot -- from ${IMAGE_ROOTFS}."
		else
                        (cd ${IMAGE_ROOTFS}; tar -cf - *) | tar xf - ||
			bbfatal "Failed to populate file system from ${IMAGE_ROOTFS}."
		fi
                popd > /dev/null 2>&1
        fi;

        bbdebug 1 "Sync'ing ${encrypted_rootfs_file} ... "
        sync; sync; sleep 5;    # Give FileBrowser time to terminate gracefully.
        bbdebug 1 "Done."

        umount mnt > /dev/null 2>&1
        ${CRYPTSETUP_BIN} luksClose ${encrypted_root_dm}
        losetup -d "${loop_dev}" > /dev/null 2>&1
        rmdir mnt > /dev/null 2>&1

	bbdebug 1 "Converting RAW image to Sparse image... "
	mv -f "${encrypted_rootfs_file}" "${encrypted_rootfs_file}.raw"
	mksparse --fillpattern=0 ${encrypted_rootfs_file}.raw ${encrypted_rootfs_file} ||
	bbfatal "Failed to convert raw image to sparse image."
        bbdebug 1 "Successfully built ${encrypted_rootfs_file}. "
}
