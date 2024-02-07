#!/bin/sh

set -ex

DISK=${FIRST}

export DEBIAN_FRONTEND=noninteractive

apt update

apt install --yes console-setup locales
apt install --yes dpkg-dev linux-headers-generic linux-image-generic
apt install --yes zfs-initramfs

echo REMAKE_INITRD=yes > /etc/dkms/zfs.conf

if [ "${BOOT_TYPE}" = "efi" ] ; then
    apt install dosfstools

    mkdosfs -F 32 -s 1 -n EFI ${DISK}-part2
    mkdir /boot/efi
    DISK_UUID=/dev/disk/by-uuid/$(blkid -s UUID -o value ${DISK}-part2)
    echo DISK: ${DISK_UUID}
    while [ ! -e ${DISK_UUID} ] ; do
	ls -Fla /dev/disk/by-uuid
	sleep 1
    done
    echo ${DISK_UUID} /boot/efi vfat defaults 0 0 >> /etc/fstab
    mount /boot/efi
    apt install --yes grub-efi-amd64 shim-signed
else
    apt install --yes grub-pc
fi

apt install --yes openssh-server
apt install --yes popularity-contest

SHELLS=$(awk -F : '{print $7}' /etc/passwd | sort -u)
for SHELL in $SHELLS ; do
    if ! dpkg-query -S "${SHELL}" ; then
	apt install --yes $(basename "${SHELL}") || true
    fi
done

grub-probe /boot
update-initramfs -c -k all

sed -i \
    -e 's,GRUB_CMDLINE_LINUX=.*,GRUB_CMDLINE_LINUX="root=ZFS='${DSET_MAIN}'",' \
    -e 's/#GRUB_TERMINAL/GRUB_TERMINAL/' \
    -e 's/"quiet"/""/' \
    /etc/default/grub

apt purge --yes os-prober
update-grub
if [ "${BOOT_TYPE}" = "efi" ] ; then
    grub-install --target=x86_64-efi --efi-directory=/boot/efi \
		 --bootloader-id=debian --recheck --no-floppy
else
    for DISK in ${DISK_ORDER} ; do
	grub-install ${DISK}
    done
fi

