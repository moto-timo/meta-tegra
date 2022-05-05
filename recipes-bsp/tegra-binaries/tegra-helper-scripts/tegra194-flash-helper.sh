#!/bin/bash
bup_blob=0
keyfile=
sbk_keyfile=
user_keyfile=
user_keyfile_for_eks=
spi_only=
sdcard=
no_flash=0
flash_cmd=
imgfile=
dataimg=
bootpartimg=
enc_imgfile=
enc_dataimg=
unique_pass=no
inst_args=""
blocksize=4096

ARGS=$(getopt -n $(basename "$0") -l "bup,no-flash,sdcard,spi-only,datafile:,usb-instance:,user_key:,encrypted,unique-pass" -o "u:v:s:b:B:yc:" -- "$@")
if [ $? -ne 0 ]; then
    echo "Error parsing options" >&2
    exit 1
fi
eval set -- "$ARGS"
unset ARGS

while true; do
    case "$1" in
	--bup)
	    bup_blob=1
	    no_flash=1
	    shift
	    ;;
	--no-flash)
	    no_flash=1
	    shift
	    ;;
	--sdcard)
	    sdcard=yes
	    shift
	    ;;
	--spi-only)
	    spi_only=yes
	    shift
	    ;;
	--datafile)
	    dataimg="$2"
	    shift 2
	    ;;
	--usb-instance)
	    usb_instance="$2"
	    inst_args="--instance ${usb_instance}"
	    shift 2
	    ;;
	--user_key)
	    user_keyfile="$2"
	    # sed -e 's/ 0x//g' -e 's/0x//' user_key_for_flash_hex_file
	    # to make the equivalent user_key_for_eks_hex_file
	    shift 2
	    ;;
	--encrypted)
	    encrypted=yes
	    shift
	    ;;
	--unique-pass)
	    unique_pass=yes
	    shift
	    ;;
	-u)
	    keyfile="$2"
	    shift 2
	    ;;
	-v)
	    sbk_keyfile="$2"
	    shift 2
	    ;;
	-s)
	    make_sdcard_args="$make_sdcard_args -s $2"
	    shift 2
	    ;;
	-b)
	    make_sdcard_args="$make_sdcard_args -b $2"
	    shift 2
	    ;;
	-B)
	    blocksize="$2"
	    shift 2
	    ;;
	-y)
	    make_sdcard_args="$make_sdcard_args -y"
	    shift
	    ;;
	-c)
	    flash_cmd="$2"
	    shift 2
	    ;;
	--)
	    shift
	    break
	    ;;
	*)
	    echo "Error processing options" >&2
	    exit 1
	    ;;
    esac
done

chkerr()
{
	if [ $? -ne 0 ]; then
		if [ "$1" != "" ]; then
			echo "$1" >&2;
		else
			echo "failed." >&2;
		fi;
		exit 1;
	fi;
	if [ "$1" = "" ]; then
		echo "done.";
	fi;
}

flash_in="$1"
dtb_file="$2"
sdramcfg_files="$3"
odmdata="$4"
kernfile="$5"
imgfile="$6"
shift 6

here=$(readlink -f $(dirname "$0"))
flashappname="tegraflash.py"

if [ ! -e ./flashvars ]; then
    echo "ERR: missing flash variables file" >&2
    exit 1
fi

. ./flashvars

if [ -z "$FLASHVARS" ]; then
    echo "ERR: flash variable set not defined" >&2
    exit 1
fi

# Temp file for storing cvm.bin in, if we need to query the board for its
# attributes
cvm_bin=$(mktemp cvm.bin.XXXXX)

skipuid=""
if [ -z "$CHIPREV" ]; then
    if [ -n "$BR_CID" ]; then
	chipid=$BR_CID
    else
        chipid=`$here/tegrarcm_v2 --uid | grep BR_CID | cut -d' ' -f2`
    fi
    if [ -z "$chipid" ]; then
	echo "ERR: could not retrieve chip ID" >&2
	exit 1
    fi
    if [ "${chipid:3:2}" != "80" -o "${chipid:6:2}" != "19" ]; then
	echo "ERR: chip ID mismatch for Xavier" >&2
	exit 1
    fi
    case "${chipid:2:1}" in
	8|9|d)
	    ;;
	*)
	    echo "ERR: non-production chip found" >&2
	    exit 1
	    ;;
    esac
    CHIPREV="${chipid:5:1}"
    ECID="$(echo '${chipid}' | sed -E -e 's/^0x//' -e 's/[0-9a-f]{7}/0000000/')"
    skipuid="--skipuid"
fi

if [ -z "$FAB" -o -z "$BOARDID" ]; then
    if ! python3 $flashappname ${inst_args} --chip 0x19 --applet mb1_t194_prod.bin $skipuid --soft_fuses tegra194-mb1-soft-fuses-l4t.cfg \
		 --bins "mb2_applet nvtboot_applet_t194.bin" --cmd "dump eeprom boardinfo ${cvm_bin};reboot recovery"; then
	echo "ERR: could not retrieve EEPROM board information" >&2
	exit 1
    fi
    skipuid=""
fi

if [ -n "$BOARDID" ]; then
    boardid="$BOARDID"
else
    boardid=`$here/chkbdinfo -i ${cvm_bin} | tr -d '[:space:]'`
    BOARDID="$boardid"
fi
if [ -n "$FAB" ]; then
    board_version="$FAB"
else
    board_version=`$here/chkbdinfo -f ${cvm_bin} | tr -d '[:space:]' | tr [a-z] [A-Z]`
    FAB="$board_version"
fi
if [ -n "$BOARDSKU" ]; then
    board_sku="$BOARDSKU"
else
    board_sku=`$here/chkbdinfo -k ${cvm_bin} | tr -d '[:space:]' | tr [a-z] [A-Z]`
    BOARDSKU="$board_sku"
fi
if [ "${BOARDREV+isset}" = "isset" ]; then
    board_revision="$BOARDREV"
else
    board_revision=`$here/chkbdinfo -r ${cvm_bin} | tr -d '[:space:]' | tr [a-z] [A-Z]`
    BOARDREV="$board_revision"
fi

[ -f ${cvm_bin} ] && rm -f ${cvm_bin}

# Adapted from p2972-0000.conf.common in L4T kit
TOREV="a01"
BPFDTBREV="a01"
PMICREV="a01"

case "$boardid" in
    2888)
	case $board_version in
	    [01][0-9][0-9])
	    ;;
	    2[0-9][0-9])
		TOREV="a02"
		PMICREV="a02"
		BPFDTBREV="a02"
		;;
	    [34][0-9][0-9])
		TOREV="a02"
		PMICREV="a04"
		BPFDTBREV="a02"
		if [ $board_sku -ge 4 ] || [ $board_version -gt 300 -a `expr "$board_revision" \> "D.0"` -eq 1 ]; then
		    PMICREV="a04-E-0"
		    BPFDTBREV="a04"
		fi
		;;
	    *)
		echo "ERR: unrecognized board version $board_version" >&2
		exit 1
		;;
	esac
	if [ "$board_sku" = "0005" ]; then
	    # AGX Xavier 64GB
	    BPFDTBREV="0005-a04-maxn"
	fi
	;;
    3668)
	# No revision-specific settings
	;;
    *)
	echo "ERR: unrecognized board ID $boardid" >&2
	exit 1
	;;
esac

ramcodeargs=
if [ "$boardid" = "2888" -a "$board_sku" = "0008" ]; then
    # AGX Xavier Industrial
    ramcodeargs="--ramcode 1"
fi

for var in $FLASHVARS; do
    eval pat=$`echo $var`
    if [ -z "${pat+definedmaybeempty}" ]; then
	echo "ERR: missing variable: $var" >&2
	exit 1
    elif [ -n "$pat" ]; then
	val=$(echo $pat | sed -e"s,@BPFDTBREV@,$BPFDTBREV," -e"s,@BOARDREV@,$TOREV," -e"s,@PMICREV@,$PMICREV," -e"s,@CHIPREV@,$CHIPREV,")
	eval $var='$val'
    fi
done

[ -n "$BOARDID" ] || BOARDID=2888
[ -n "$FAB" ] || FAB=400
[ -n "$fuselevel" ] || fuselevel=fuselevel_production
[ -n "${BOOTDEV}" ] || BOOTDEV="mmcblk0p1"

rm -f ${MACHINE}_bootblob_ver.txt
echo "NV3" >${MACHINE}_bootblob_ver.txt
. bsp_version
echo "# R$BSP_BRANCH , REVISION: $BSP_MAJOR.$BSP_MINOR" >>${MACHINE}_bootblob_ver.txt
echo "BOARDID=$BOARDID BOARDSKU=$BOARDSKU FAB=$FAB" >>${MACHINE}_bootblob_ver.txt
date "+%Y%m%d%H%M%S" >>${MACHINE}_bootblob_ver.txt
bytes=`cksum ${MACHINE}_bootblob_ver.txt | cut -d' ' -f2`
cksum=`cksum ${MACHINE}_bootblob_ver.txt | cut -d' ' -f1`
echo "BYTES:$bytes CRC32:$cksum" >>${MACHINE}_bootblob_ver.txt
if [ -z "$sdcard" ]; then
    appfile=$(basename "$imgfile").img
    if [ -n "$dataimg" ]; then
	datafile=$(basename "$dataimg").img
    fi
else
    appfile="$imgfile"
    datafile="$dataimg"
fi
appfile_sed=
if [ $bup_blob -ne 0 ]; then
    kernfile="${kernfile:-boot.img}"
    appfile_sed="-e/APPFILE/d -e/DATAFILE/d"
elif [ $no_flash -eq 0 -a -z "$sdcard" ]; then
    appfile_sed="-es,APPFILE,$appfile, -es,DATAFILE,$datafile,"
else
    pre_sdcard_sed="-es,APPFILE,$appfile,"
    if [ -n "$datafile" ]; then
	pre_sdcard_sed="$pre_sdcard_sed -es,DATAFILE,$datafile,"
	touch DATAFILE
    fi
    touch APPFILE
fi

dtb_file_basename=$(basename "$dtb_file")
kernel_dtbfile="kernel_$dtb_file_basename"
rm -f "$kernel_dtbfile"
cp "$dtb_file" "$kernel_dtbfile"

if [ "$spi_only" = "yes" ]; then
    if [ ! -e "$here/nvflashxmlparse" ]; then
	echo "ERR: missing nvflashxmlparse script" >&2
	exit 1
    fi
    "$here/nvflashxmlparse" --extract -t spi -o flash.xml.tmp "$flash_in" || exit 1
else
    cp "$flash_in" flash.xml.tmp
fi
sed -e"s,VERFILE,${MACHINE}_bootblob_ver.txt," -e"s,BPFDTB_FILE,$BPFDTB_FILE," \
    -e"s,TBCDTB-FILE,$dtb_file," -e"s, DTB_FILE,$kernel_dtbfile," \
    $appfile_sed flash.xml.tmp > flash.xml
rm flash.xml.tmp

BINSARGS="mb2_bootloader nvtboot_recovery_t194.bin; \
mts_preboot preboot_c10_prod_cr.bin; \
mts_mce mce_c10_prod_cr.bin; \
mts_proper mts_c10_prod_cr.bin; \
bpmp_fw bpmp_t194.bin; \
bpmp_fw_dtb $BPFDTB_FILE; \
spe_fw spe_t194.bin; \
tlk tos-trusty_t194.img; \
eks eks.img; \
bootloader_dtb $dtb_file"

bctargs="$UPHY_CONFIG $MINRATCHET_CONFIG $TRIM_BPMP_DTB \
         --device_config $DEVICE_CONFIG \
         --misc_config tegra194-mb1-bct-misc-flash.cfg \
         --misc_cold_boot_config $MISC_COLD_BOOT_CONFIG \
         --pinmux_config $PINMUX_CONFIG \
         --gpioint_config $GPIOINT_CONFIG \
         --pmic_config $PMIC_CONFIG \
         --pmc_config $PMC_CONFIG \
         --prod_config $PROD_CONFIG \
         --scr_config $SCR_CONFIG \
         --scr_cold_boot_config $SCR_COLD_BOOT_CONFIG \
         --br_cmd_config $BR_CMD_CONFIG \
         --dev_params $DEV_PARAMS"


if [ $bup_blob -ne 0 -o "$sdcard" = "yes" ]; then
    tfcmd=sign
    skipuid="--skipuid"
else
    if [ -z "$sdcard" -a $no_flash -eq 0 ]; then
	rm -f "$appfile"
	$here/mksparse -b ${blocksize} --fillpattern=0 "$imgfile" "$appfile" || exit 1
	if [ -n "$datafile" ]; then
	    rm -f "$datafile"
	    $here/mksparse -b ${blocksize} --fillpattern=0 "$dataimg" "$datafile" || exit 1
	fi
    fi
    tfcmd=${flash_cmd:-"flash;reboot"}
fi

if [ "$encrypted" == "yes" ]; then
    if [ -x $here/disk_encryption/gen_luks_passphrase.py ]; then
	genpassphrase="$here/disk_encryption/gen_luks_passphrase.py";
    else
	hereparent=$(readlink -f "$here/.." 2>/dev/null)
	if [ -n "$hereparent" -a -x "$hereparent/disk_encryption/gen_luks_passphrase.py" ]; then
	    genpassphrase="$hereparent/disk_encryption/gen_luks_passphrase.py"
	fi
    fi
    if [ -z "$genpassphrase" ]; then
	echo "ERR: missing disk_encryption/gen_luks_passphrase.py script" >&2
	exit 1
    fi
    if [ -f $here/disk_encryption/disk_encryption_helper.func ]; then
	diskenchelper="$here/disk_encryption/disk_encryption_helper.func";
    else
	hereparent=$(readlink -f "$here/.." 2>/dev/null)
	if [ -n "$hereparent" -a -x "$hereparent/disk_encryption/disk_encryption_helper.func" ]; then
	    diskenchelper="$hereparent/disk_encryption/disk_encryption_helper.func"
	fi
    fi
    if [ -z "$diskenchelper" ]; then
	echo "ERR: missing disk_encryption/disk_encryption_helper.func" >&2
	exit 1
    fi
    if [ -z "$CRYPTSETUP_BIN" ]; then
	CRYPTSETUP_BIN=$(which cryptsetup)
    fi
    if [ ! -x "$CRYPTSETUP_BIN" ]; then
        echo "ERR: missing cryptsetup, try 'sudo apt install cryptsetup'" >&2
	exit 1
    fi
    if [ -z "${APP_ENC_UUID}" ]; then
        APP_ENC_UUID=$(xmllint \
          --xpath "partition_layout/device[@type='sdmmc_user']/partition[@name='APP_ENC']/unique_guid/text()" \
          $flash_in | tr -d ' ')
    fi
    if [ "$unique_guid" == "yes" ]; then
        if [ -z "$user_keyfile_for_eks" ]; then
            echo "ERR: --unique-guid requires --user-key user_key_file" >&2
	    exit 1
	fi
	if [ -z "${ECID}" ]; then
            echo "ERR: --unique-guid requires either BR_CID= variable or connection to the device in recovery mode." >&2
	    exit 1
	fi
	GEN_LUKS_PASSPHRASE_ARGS="--context-string ${APP_ENC_UUID} --unique-pass --key-file $user_keyfile_for_eks --ecid ${ECID}"
    else
        GEN_LUKS_PASSPHRASE_ARGS="--context-string ${APP_ENC_UUID} --generic-pass"
    fi
    if [ -z "${GEN_LUKS_PASSPHRASE_CMD}" ]; then
        GEN_LUKS_PASSPHRASE_CMD="${genpassphrase} ${GEN_LUKS_PASSPHRASE_ARGS}"
    fi

    if [ -z "${ROOTFSPART_SIZE}" ]; then
        ROOTFSPART_SIZE=$(xmllint \
          --xpath "partition_layout/device[@type='sdmmc_user']/partition[@name='APP_ENC']/size/text()" \
          $flash_in | tr -d ' ')
    fi

    source_fstype="tar.gz"
    fstype="ext4"
    rm -rf rootfs
    mkdir -p rootfs
    pushd rootfs > /dev/null 2>&1
    echo "DEBUG: Unpacking rootfs..."
    tar xzf ../${imgfile}
    chkerr "ERR: Unpacking rootfs tar.gz failed, is ${imgfile} a gzipped tar archive? Try setting IMAGE_TEGRAFLASH_FS_TYPE = \"tar.gz\" in your local.conf for the build."
    popd
    IMAGE_ROOTFS=${PWD}/rootfs

    # Create initial disk image

    # If generating an empty image the size of the sparse block should be large
    # enough to allocate an ext4 filesystem using 4096 bytes per inode, this is
    # about 60K, so dd needs a minimum count of 60, with bs=1024 (bytes per IO)
    eval COUNT="0"
    eval MIN_COUNT="60"
    let ROOTFS_SIZE=($ROOTFSPART_SIZE / 1024)
    if [ $ROOTFS_SIZE -lt $MIN_COUNT ]; then
        eval COUNT="$MIN_COUNT"
    fi

    base_imgfile=$(echo ${imgfile} | sed -e 's/.tar.gz//')
    encrypted_rootfs_file="${base_imgfile}.${fstype}.encrypted"

    # Create a sparse image block
    echo "DEBUG: Executing 'dd if=/dev/zero of=${encrypted_rootfs_file} seek=$ROOTFS_SIZE count=$COUNT bs=1024'"
    dd if=/dev/zero of=${encrypted_rootfs_file} seek=$ROOTFS_SIZE count=$COUNT bs=1024
    echo "DEBUG: Actual Rootfs size:  `du -s ${IMAGE_ROOTFS}`"
    echo "DEBUG: Actual Partion size: `stat -c '%s' ${encrypted_rootfs_file}`"

    # Create loopback device
    # NOTE: _MUST_ run with sudo/root privileges
    echo "DEBUG: Executing losetup --show -f '${encrypted_rootfs_file}'"
    loop_dev="$(losetup --show -f "${encrypted_rootfs_file}")"

    encrypted_root_dm="tegra_encrypted_root"
    encrypted_root_dm_dev="/dev/mapper/${encrypted_root_dm}"

    disk_uuid="${APP_ENC_UUID}"
    echo -n -e "${disk_uuid}" > ${encrypted_rootfs_file}.uuid

    echo "DEBUG: ${GEN_LUKS_PASSPHRASE_CMD}"
    passphrase=`${GEN_LUKS_PASSPHRASE_CMD}`

    CRYPTSETUP_DEVICE_TYPE="luks1"
    CRYPTSETUP_CIPHER="aes-cbc-essiv:sha256"
    CRYPTSETUP_KEY_SIZE="128"

    # Add the LUKS header.
    echo "DEBUG: disk_uuid = ${disk_uuid}"
    echo "DEBUG: loop_dev = ${loop_dev}"
    echo "DEBUG: passphrase = ${passphrase}"
    echo -n ${passphrase} | ${CRYPTSETUP_BIN} \
            --type ${CRYPTSETUP_DEVICE_TYPE} \
            --cipher ${CRYPTSETUP_CIPHER} \
            --key-size ${CRYPTSETUP_KEY_SIZE} \
            --uuid ${disk_uuid} \
            luksFormat \
            ${loop_dev}
    chkerr "ERR: Adding LUKS header to ${encrypted_rootfs_file} failed. ${$?}"

    # Unlock the encrypted filesystem image.
    if [ -e "${encrypted_root_dm_dev}" ]; then
        umount ${encrypted_root_dm_dev}
        ${CRYPTSETUP_BIN} luksClose ${encrypted_root_dm}
    fi
    echo -n ${passphrase} | ${CRYPTSETUP_BIN} \
            luksOpen ${loop_dev} ${encrypted_root_dm}
        chkerr "ERR: Unlocking ${encrypted_rootfs_file} failed."

    echo "DEBUG: Executing mkfs.$fstype -F $extra_imagecmd ${encrypted_root_dm_dev}"
    mkfs.$fstype -F $extra_imagecmd ${encrypted_root_dm_dev} > /dev/null 2>&1
    chkerr "ERR: Formating ${fstype} filesystem on ${encrypted_root_dm_dev} failed."
    mkdir -p mnt
    chkerr "ERR: Making ${encrypted_rootfs_file} mount point failed."
    mount ${encrypted_root_dm_dev} mnt
    chkerr "ERR: Mounting ${encrypted_rootfs_file} failed."

    # Processing partition data.
    if [ "${IMAGE_ROOTFS}" != "" ]; then
        pushd mnt > /dev/null 2>&1
        echo "DEBUG: Populating filesystem from ${IMAGE_ROOTFS} ... "
        if [ "${UNENCRYPTED_BOOT_PART}" == "1" ]; then
            (cd ${IMAGE_ROOTFS}; tar -cf --exclude /boot - *) | tar xf -
            chkerr "ERR: Failed to populate file system -- excluding /boot -- from ${IMAGE_ROOTFS}."
        else
            (cd ${IMAGE_ROOTFS}; tar -cf - *) | tar xf -
            chkerr "ERR: Failed to populate file system from ${IMAGE_ROOTFS}."
        fi
        popd > /dev/null 2>&1
    fi;

    echo "DEBUG: Sync'ing ${encrypted_rootfs_file} ... "
    sync; sync; sleep 5;    # Give FileBrowser time to terminate gracefully.
    echo "DEBUG: Done."

    echo "DEBUG: Converting RAW image to Sparse image... "
    mv -f "${encrypted_rootfs_file}" "${encrypted_rootfs_file}.raw"
    $here/mksparse --fillpattern=0 ${encrypted_rootfs_file}.raw ${encrypted_rootfs_file}
    chkerr "ERR: Failed to convert raw image to sparse image."
    echo "DEBUG: Successfully built ${encrypted_rootfs_file}. "
    echo "DEBUG: Detaching from ${loop_dev}."
    losetup -d ${loop_dev}

    unset GEN_LUKS_PASSPHRASE_CMD
    # Create encrypted UDA partition image
    if [ -z "${UDA_ENC_UUID}" ]; then
	UDA_ENC_UUID=$(xmllint \
	  --xpath "partition_layout/device[@type='sdmmc_user']/partition[@name='UDA']/unique_guid/text()" \
	  $flash_in | tr -d ' ')
    fi
    if [ "$unique_guid" == "yes" ]; then
	if [ -z "$user_keyfile_for_eks" ]; then
	    echo "ERR: --unique-guid requires --user-key user_key_file" >&2
	    exit 1
	fi
	if [ -z "${ECID}" ]; then
	    echo "ERR: --unique-guid requires either BR_CID= variable or connection to the device in recovery mode." >&2
	    exit 1
	fi
	GEN_LUKS_PASSPHRASE_ARGS="--context-string ${UDA_ENC_UUID} --unique-pass --key-file $user_keyfile_for_eks --ecid ${ECID}"
    else
	GEN_LUKS_PASSPHRASE_ARGS="--context-string ${UDA_ENC_UUID} --generic-pass"
    fi
    if [ -z "${GEN_LUKS_PASSPHRASE_CMD}" ]; then
	GEN_LUKS_PASSPHRASE_CMD="${genpassphrase} ${GEN_LUKS_PASSPHRASE_ARGS}"
    fi

    if [ -z "${UDAPART_SIZE}" ]; then
	UDAPART_SIZE=$(xmllint \
	  --xpath "partition_layout/device[@type='sdmmc_user']/partition[@name='UDA']/size/text()" \
	  $flash_in | tr -d ' ')
    fi
    # fstype="ext4"
    # Create initial disk image

    # If generating an empty image the size of the sparse block should be large
    # enough to allocate an ext4 filesystem using 4096 bytes per inode, this is
    # about 60K, so dd needs a minimum count of 60, with bs=1024 (bytes per IO)
    eval COUNT="0"
    eval MIN_COUNT="60"
    let DATAFS_SIZE=($UDAPART_SIZE / 1024)
    if [ $DATAFS_SIZE -lt $MIN_COUNT ]; then
        eval COUNT="$MIN_COUNT"
    fi

    encrypted_datafs_file="data.${fstype}.encrypted"

    # Create a sparse image block
    echo "DEBUG: Executing 'dd if=/dev/zero of=${encrypted_datafs_file} seek=$DATAFS_SIZE count=$COUNT bs=1024'"
    dd if=/dev/zero of=${encrypted_datafs_file} seek=$DATAFS_SIZE count=$COUNT bs=1024
    echo "DEBUG: Actual Partion size: `stat -c '%s' ${encrypted_datafs_file}`"

    # Create loopback device
    # NOTE: _MUST_ run with sudo/root privileges
    echo "DEBUG: Executing losetup --show -f '${encrypted_datafs_file}'"
    loop_dev="$(losetup --show -f "${encrypted_datafs_file}")"

    encrypted_data_dm="tegra_encrypted_data"
    encrypted_data_dm_dev="/dev/mapper/${encrypted_data_dm}"

    disk_uuid="${UDA_ENC_UUID}"
    echo -n -e "${disk_uuid}" > ${encrypted_datafs_file}.uuid

    echo "DEBUG: ${GEN_LUKS_PASSPHRASE_CMD}"
    passphrase=`${GEN_LUKS_PASSPHRASE_CMD}`

    # CRYPTSETUP_DEVICE_TYPE="luks1"
    # CRYPTSETUP_CIPHER="aes-cbc-essiv:sha256"
    # CRYPTSETUP_KEY_SIZE="128"

    # Add the LUKS header.
    echo "DEBUG: disk_uuid = ${disk_uuid}"
    echo "DEBUG: loop_dev = ${loop_dev}"
    echo "DEBUG: passphrase = ${passphrase}"
    echo -n ${passphrase} | ${CRYPTSETUP_BIN} \
	    --type ${CRYPTSETUP_DEVICE_TYPE} \
	    --cipher ${CRYPTSETUP_CIPHER} \
	    --key-size ${CRYPTSETUP_KEY_SIZE} \
	    --uuid ${disk_uuid} \
	    luksFormat \
	    ${loop_dev}
    chkerr "ERR: Adding LUKS header to ${encrypted_datafs_file} failed. ${$?}"

    # Unlock the encrypted filesystem image.
    if [ -e "${encrypted_data_dm_dev}" ]; then
	umount ${encrypted_data_dm_dev}
	${CRYPTSETUP_BIN} luksClose ${encrypted_data_dm}
    fi
    echo -n ${passphrase} | ${CRYPTSETUP_BIN} \
	    luksOpen ${loop_dev} ${encrypted_data_dm}
	chkerr "ERR: Unlocking ${encrypted_datafs_file} failed."

    echo "DEBUG: Executing mkfs.$fstype -F $extra_imagecmd ${encrypted_data_dm_dev}"
    mkfs.$fstype -F $extra_imagecmd ${encrypted_data_dm_dev} > /dev/null 2>&1
    chkerr "ERR: Formating ${fstype} filesystem on ${encrypted_data_dm_dev} failed."
    mkdir -p mnt
    chkerr "ERR: Making ${encrypted_datafs_file} mount point failed."
    mount ${encrypted_data_dm_dev} mnt
    chkerr "ERR: Mounting ${encrypted_datafs_file} failed."

    # Processing partition data.
    if [ "${IMAGE_DATAFS}" != "" ]; then
	pushd mnt > /dev/null 2>&1
	echo "DEBUG: Populating filesystem from ${IMAGE_DATAFS} ... "
	(cd ${IMAGE_DATAFS}; tar -cf - *) | tar xf -
	chkerr "ERR: Failed to populate file system from ${IMAGE_DATAFS}."
	popd > /dev/null 2>&1
    fi;

    echo "DEBUG: Sync'ing ${encrypted_datafs_file} ... "
    sync; sync; sleep 5;    # Give FileBrowser time to terminate gracefully.
    echo "DEBUG: Done."

    echo "DEBUG: Converting RAW image to Sparse image... "
    mv -f "${encrypted_datafs_file}" "${encrypted_datafs_file}.raw"
    $here/mksparse --fillpattern=0 ${encrypted_datafs_file}.raw ${encrypted_datafs_file}
    chkerr "ERR: Failed to convert raw image to sparse image."
    echo "DEBUG: Successfully built ${encrypted_datafs_file}. "
    echo "DEBUG: Detaching from ${loop_dev}."
    losetup -d ${loop_dev}

fi # end encrypted

temp_user_dir=
if [ -n "$keyfile" ]; then
    if [ -n "$sbk_keyfile" ]; then
	if [ -z "$user_keyfile" ]; then
	    rm -f "null_user_key.txt"
	    echo "0x00000000 0x00000000 0x00000000 0x00000000" > null_user_key.txt
	    user_keyfile=$(readlink -f null_user_key.txt)
	fi
	if [ -z "$user_keyfile_for_eks" ]; then
	    rm -f "null_user_key_for_eks.txt"
	    echo "00000000000000000000000000000000" > null_user_key_for_eks.txt
	    user_keyfile_for_eks=$(readlink -f null_user_key_for_eks.txt)
	else
	    sed -e 's/ 0x//g' -e 's/0x//' $user_keyfile > user_key_for_eks.txt
	    user_keyfile_for_eks=$(readlink -f user_key_for_eks.txt)
	fi
	rm -rf signed_bootimg_dir
	mkdir signed_bootimg_dir
	cp "$kernfile" "$kernel_dtbfile" signed_bootimg_dir/
	if [ -n "$MINRATCHET_CONFIG" ]; then
	    for f in $MINRATCHET_CONFIG; do
		[ -e "$f" ] || continue
		cp "$f" signed_bootimg_dir/
	    done
	fi
	oldwd="$PWD"
	cd signed_bootimg_dir
	if [ -x $here/l4t_sign_image.sh ]; then
	    signimg="$here/l4t_sign_image.sh";
	else
	    hereparent=$(readlink -f "$here/.." 2>/dev/null)
	    if [ -n "$hereparent" -a -x "$hereparent/l4t_sign_image.sh" ]; then
		signimg="$hereparent/l4t_sign_image.sh"
	    fi
	fi
	if [ -z "$signimg" ]; then
	    echo "ERR: missing l4t_sign_image script" >&2
	    exit 1
	fi
	"$signimg" --file "$kernfile"  --key "$keyfile" --encrypt_key "$user_keyfile" --chip 0x19 --split False $MINRATCHET_CONFIG &&
	    "$signimg" --file "$kernel_dtbfile"  --key "$keyfile" --encrypt_key "$user_keyfile" --chip 0x19 --split False $MINRATCHET_CONFIG
	rc=$?
	cd "$oldwd"
	if [ $rc -ne 0 ]; then
	    echo "Error signing kernel image or device tree" >&2
	    exit 1
	fi
	temp_user_dir=signed_bootimg_dir
    fi

    CHIPID="0x19"
    tegraid="$CHIPID"
    localcfgfile="flash.xml"
    dtbfilename="$kernel_dtbfile"
    tbcdtbfilename="$dtb_file"
    bpfdtbfilename="$BPFDTB_FILE"
    localbootfile="$kernfile"
    BINSARGS="--bins \"$BINSARGS\""
    flashername=nvtboot_recovery_cpu_t194.bin
    BCT="--sdram_config"
    bctfilename=`echo $sdramcfg_files | cut -d, -f1`
    bctfile1name=`echo $sdramcfg_files | cut -d, -f2`
    SOSARGS="--applet mb1_t194_prod.bin "
    NV_ARGS="--soft_fuses tegra194-mb1-soft-fuses-l4t.cfg "
    BCTARGS="$bctargs"
    rootfs_ab=0
    rcm_boot=0
    external_device=0
    . "$here/odmsign.func"
    (odmsign_ext) || exit 1
    if [ $bup_blob -eq 0 -a $no_flash -ne 0 ]; then
	if [ -f flashcmd.txt ]; then
	    chmod +x flashcmd.txt
	    ln -sf flashcmd.txt ./secureflash.sh
	else
	    echo "WARN: signing completed successfully, but flashcmd.txt missing" >&2
	fi
	rm -f APPFILE DATAFILE null_user_key.txt
    fi
    if [ $bup_blob -eq 0 ]; then
	if [ -n "$temp_user_dir" ]; then
	    cp "$temp_user_dir"/*.encrypt.signed .
	    rm -rf "$temp_user_dir"
	fi
	exit 0
    fi
    touch odmsign.func
fi

flashcmd="python3 $flashappname ${inst_args} --chip 0x19 --bl nvtboot_recovery_cpu_t194.bin \
	      --sdram_config $sdramcfg_files \
	      --odmdata $odmdata \
	      --applet mb1_t194_prod.bin \
	      --soft_fuses tegra194-mb1-soft-fuses-l4t.cfg \
	      --cmd \"$tfcmd\" $skipuid \
	      --cfg flash.xml \
	      $bctargs $ramcodeargs \
	      --bins \"$BINSARGS\""

if [ $bup_blob -ne 0 ]; then
    [ -z "$keyfile" ] || flashcmd="${flashcmd} --key \"$keyfile\""
    [ -z "$sbk_keyfile" ] || flashcmd="${flashcmd} --encrypt_key \"$sbk_keyfile\""
    support_multi_spec=1
    clean_up=0
    dtbfilename="$kernel_dtbfile"
    tbcdtbfilename="$dtb_file"
    bpfdtbfilename="$BPFDTB_FILE"
    localbootfile="boot.img"
    . "$here/l4t_bup_gen.func"
    spec="${BOARDID}-${FAB}-${BOARDSKU}-${BOARDREV}-1-${CHIPREV}-${MACHINE}-${BOOTDEV}"
    if [ $(expr length "$spec") -ge 64 ]; then
	echo "ERR: TNSPEC must be shorter than 64 characters: $spec" >&2
	exit 1
    fi
    l4t_bup_gen "$flashcmd" "$spec" "$fuselevel" t186ref "$keyfile" "$sbk_keyfile" 0x19 || exit 1
else
    eval $flashcmd < /dev/null || exit 1
    if [ -n "$sdcard" ]; then
	if [ -n "$pre_sdcard_sed" ]; then
	    rm -f signed/flash.xml.tmp.in
	    mv signed/flash.xml.tmp signed/flash.xml.tmp.in
	    sed $pre_sdcard_sed  signed/flash.xml.tmp.in > signed/flash.xml.tmp
	fi
	$here/make-sdcard $make_sdcard_args signed/flash.xml.tmp "$@"
    fi
fi
