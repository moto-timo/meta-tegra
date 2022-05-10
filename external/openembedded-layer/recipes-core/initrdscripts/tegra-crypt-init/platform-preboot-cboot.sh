echo "platform-preboot: begin" > /dev/kmsg

dev_regex='root=\/dev\/[abcdefklmnpsv0-9]*'
uuid_regex='root=PARTUUID=[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
rootdev="$(cat /proc/cmdline | grep -oE "\<${dev_regex}|${uuid_regex}\>" | tail -1)"
if [ "${rootdev}" != "" ]; then
	if [[ "${rootdev}" =~ "PARTUUID" ]]; then
		rootdev=$(echo "${rootdev}" | sed -ne "s/root=\(.*\)/\1/p")
	else
		rootdev=$(echo "${rootdev}" | sed -ne "s/root=\/dev\/\(.*\)/\1/p")
	fi
	echo "Root device found: ${rootdev}" > /dev/kmsg;
fi


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
                        echo "platform-preboot: ERROR: encrypted dev ${enc_dev} is not LUKS device." > /dev/kmsg;
                        exec sh;
                fi;

                # Unlock the encrypted dev
                /usr/sbin/luks-srv-app -u -c "${crypt_disk_uuid}" |
                        /usr/sbin/cryptsetup luksOpen "${enc_dev}" "${enc_dm_name}";
                if [ $? -ne 0 ]; then
                        echo "platform-preboot: ERROR: fail to unlock the encrypted dev ${enc_dev}." > /dev/kmsg;
                        exec sh;
                fi;

                if [ ${enc_dev_match_root} -eq 1 ]; then
                        mount "/dev/mapper/${enc_dm_name}" /mnt/;
                else
			mkdir "/mnt/mnt/${enc_dm_name}";
                        mount "/dev/mapper/${enc_dm_name}" "/mnt/mnt/${enc_dm_name}";
                fi;
        done < /etc/crypttab;
fi
echo "platform-preboot: end" > /dev/kmsg
