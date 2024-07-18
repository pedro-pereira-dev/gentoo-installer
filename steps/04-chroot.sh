#!/bin/bash

clear
echo -e '
  ______   __             _                           
 / __   | / /            | |                     _    
| | //| |/ /____ ___ ____| | _   ____ ___   ___ | |_  
| |// | |___   _|___) ___) || \ / ___) _ \ / _ \|  _) 
|  /__| |   | |    ( (___| | | | |  | |_| | |_| | |__ 
 \_____/    |_|     \____)_| |_|_|   \___/ \___/ \___)
______________________________________________________
'

# mounts system
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run
mount --make-slave /mnt/gentoo/run
test -L /dev/shm && rm /dev/shm && mkdir /dev/shm
mount --types tmpfs --options nosuid,nodev,noexec shm /dev/shm
chmod 1777 /dev/shm /run/shm

# exports required variables
export THIS_DEVICE THIS_DEVICE_SEPARATOR THIS_TIMEZONE THIS_HOST THIS_PASSWORD THIS_KEYMAP THIS_USER
# creates chroot scripts
mkdir -p /mnt/gentoo/installation-scripts
envsubst <${STEPS_DIR}/05-installing-base.sh >/mnt/gentoo/installation-scripts/05-installing-base.sh
envsubst <${STEPS_DIR}/06-installing-kernel.sh >/mnt/gentoo/installation-scripts/06-installing-kernel.sh
envsubst <${STEPS_DIR}/07-configuring-system.sh >/mnt/gentoo/installation-scripts/07-configuring-system.sh

# chroots into system
chroot /mnt/gentoo /bin/bash <<EOF
source /etc/profile && export PS1="(chroot) \${PS1}"

source /installation-scripts/05-installing-base.sh
source /installation-scripts/06-installing-kernel.sh
source /installation-scripts/07-configuring-system.sh

eselect news read >/dev/null 2>&1
emerge --ask=n --depclean

rm /stage3-*.tar.*
rm -rf /installation-scripts
EOF
