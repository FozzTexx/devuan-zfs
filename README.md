Currently there's no way to install Devuan as pure ZFS with the
installer. Instead what I'm doing is putting an extra small disk in
the computer, doing a minimal Devuan install to that disk, booting
from it, and then running this to do a new install to all the disks
that will be ZFS. After the ZFS setup the initial disk is removed from
the system.

https://openzfs.github.io/openzfs-docs/Getting%20Started/Debian/Debian%20Bullseye%20Root%20on%20ZFS.html#step-3-system-installation

Packages needed:

* debootstrap
* gdisk
* zfs-dkms
* zfsutils-linux

Run setup-zfs.sh, setup-zfs-stage2.sh will be run from inside the chroot by setup-zfs.sh

