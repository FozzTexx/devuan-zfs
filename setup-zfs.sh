#!/bin/sh

set -e

POOL_BOOT="boot"
POOL_MAIN="main"
COLL=$(hostname -s)
MNT=/mnt

umount -R ${MNT} || true

FIRST=ZSNL
DISKS=$(ls /dev/disk/by-id/ata-ST18000NM000J* | grep -v -e '-part[0-9]*$')

for DISK in ${DISKS} ; do
    if echo ${DISK} | grep -q ${FIRST} ; then
	FIRST=${DISK}
	DISK_ORDER="${DISK_ORDER} ${DISK}"
    else
	DISK_UNORDER="${DISK_UNORDER} ${DISK}"
    fi
done
DISK_ORDER="${DISK_ORDER} ${DISK_UNORDER}"

for DISK in ${DISK_ORDER} ; do
    sgdisk --zap-all ${DISK}
    sgdisk     -n2:1M:+512M   -t2:EF00 $DISK
    sgdisk     -n3:0:+1G      -t3:BF01 $DISK
    sgdisk     -n4:0:0        -t4:BF00 $DISK
    DISKS_BOOT="${DISKS_BOOT} ${DISK}-part3"
    DISKS_MAIN="${DISKS_MAIN} ${DISK}-part4"
done

sleep 1

# Create boot pool
zpool destroy ${POOL_BOOT} || true
zpool create -f \
    -o ashift=12 \
    -o autotrim=on \
    -o compatibility=grub2 \
    -o cachefile=/etc/zfs/zpool.cache \
    -O devices=off \
    -O acltype=posixacl -O xattr=sa \
    -O compression=lz4 \
    -O normalization=formD \
    -O relatime=on \
    -O canmount=off -O mountpoint=/boot -R ${MNT} \
    ${POOL_BOOT} mirror ${DISKS_BOOT}

# Create root pool
zpool destroy ${POOL_MAIN} || true
zpool create -f \
    -o ashift=12 \
    -o autotrim=on \
    -O acltype=posixacl -O xattr=sa -O dnodesize=auto \
    -O compression=lz4 \
    -O normalization=formD \
    -O relatime=on \
    -O canmount=off -O mountpoint=/ -R ${MNT} \
    ${POOL_MAIN} raidz2 ${DISKS_MAIN}

DSET_BOOT="${POOL_BOOT}/BOOT"
DSET_MAIN="${POOL_MAIN}/MAIN"

zfs create -o canmount=off -o mountpoint=none ${DSET_MAIN}
zfs create -o canmount=off -o mountpoint=none ${DSET_BOOT}

zfs create -o canmount=noauto -o mountpoint=/ ${DSET_MAIN}/${COLL}
zpool set bootfs=${DSET_MAIN}/${COLL} ${POOL_MAIN}
zfs mount ${DSET_MAIN}/${COLL}

zfs create -o mountpoint=/boot ${DSET_BOOT}/${COLL}

zfs create                     ${POOL_MAIN}/home
zfs create -o mountpoint=/root ${POOL_MAIN}/home/root
chmod 700 ${MNT}/root
zfs create -o canmount=off     ${POOL_MAIN}/var
zfs create -o canmount=off     ${POOL_MAIN}/var/lib
zfs create                     ${POOL_MAIN}/var/log
zfs create                     ${POOL_MAIN}/var/spool

zfs create -o com.sun:auto-snapshot=false ${POOL_MAIN}/var/lib/docker

. /etc/*release

echo "#####################"
echo "Doing base OS install"
echo "#####################"
echo
debootstrap ${VERSION_CODENAME} ${MNT}

mkdir ${MNT}/etc/zfs
cp /etc/zfs/zpool.cache ${MNT}/etc/zfs/

INTERFACE=$(ip route| grep default | awk '{print $NF}')
IF_CONFIG=${MNT}/etc/network/interfaces.d/${INTERFACE}
echo "auto ${INTERFACE}" >> ${IF_CONFIG}
echo "iface ${INTERFACE} inet dhcp" >> ${IF_CONFIG}
TOCOPY="/etc/apt/sources.list /etc/locale.gen /etc/default/locale /etc/timezone /etc/default/keyboard /etc/passwd /etc/group /etc/shadow /etc/gshadow /etc/hostname"
for FILE in ${TOCOPY} ; do
    echo copying ${FILE}
    cp ${FILE} ${MNT}${FILE}
done

mount --make-private --rbind /dev  ${MNT}/dev
mount --make-private --rbind /proc ${MNT}/proc
mount --make-private --rbind /sys  ${MNT}/sys

# Do stage 2
cp setup-zfs-stage2.sh ${MNT}/root
chroot ${MNT} /usr/bin/env \
       "TERM=vt100" \
       "DISK_ORDER=$DISK_ORDER" \
       "FIRST=${FIRST}" \
       "DSET_MAIN=${DSET_MAIN}" \
       "POOL_BOOT=${POOL_BOOT}" \
       "POOL_MAIN=${POOL_MAIN}" \
       /root/setup-zfs-stage2.sh
