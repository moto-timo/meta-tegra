slotsfx=""
mayberoot=""
for bootarg in `cat /proc/cmdline`; do
    case "$bootarg" in
	boot.slot_suffix=*) slotsfx="${bootarg##boot.slot_suffix=}" ;;
	root=*) mayberoot="${bootarg##root=}" ;;
	ro) opt="ro" ;;
	rootwait) wait="yes" ;;
    esac
done
rootdev=`blkid -l -t PARTLABEL=APP$slotsfx | cut -d: -f1`
if [ -e "/etc/crypttab" ]; then
        ext4uuid_regex='root=UUID=[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
        encrootcmd="$(cat /proc/cmdline | grep -oE "\<${dev_regex}|${ext4uuid_regex}\>" | tail -1)";
        rootext4uuid="$(echo ${encrootcmd} | awk -F "=" '{print $3}')";

        while read crypttab_line
        do
                enc_dm_name="$(echo "${crypttab_line}" | awk -F " " '{print $1}')";
                crypt_dev="$(echo "${crypttab_line}" | awk -F " " '{print $2}')";
                crypt_disk_uuid="$(echo "${crypt_dev}" | awk -F "=" '{print $2}')";
                enc_dev_match_root=$(echo "${crypt_dev}" | grep -cE "${rootext4uuid}");
                enc_dev=$(blkid | grep -E "${crypt_disk_uuid}" | awk -F ":" '{print $1}');

                # isLuks
                /usr/sbin/cryptsetup isLuks "${enc_dev}";
                if [ $? -ne 0 ]; then
                        echo "ERROR: encrypted dev ${enc_dev} is not LUKS device.";
                        exec /bin/bash;
                fi;

                # Unlock the encrypted dev
                luks-srv-app -u -c "${crypt_disk_uuid}" |
                        /usr/sbin/cryptsetup luksOpen "${enc_dev}" "${enc_dm_name}";
                if [ $? -ne 0 ]; then
                        echo "ERROR: fail to unlock the encrypted dev ${enc_dev}.";
                        exec /bin/bash;
                fi;

                if [ ${enc_dev_match_root} -eq 1 ]; then
                        mount "/dev/mapper/${enc_dm_name}" /mnt/;
                else
                        mount "/dev/mapper/${enc_dm_name}" "/mnt/mnt/${enc_dm_name}";
                fi;
        done < /etc/crypttab;
elif [ -z "$rootdev" ]; then
    if [ -n "$mayberoot" ]; then
	rootdev="$mayberoot"
    else
	rootdev="/dev/mmcblk0p1"
    fi
fi
