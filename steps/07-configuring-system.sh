#!/bin/bash

clear
echo -e '
  ______ _______                     ___ _                   _                                                
 / __   (_______)                   / __|_)                 (_)                               _               
| | //| |     _ ___ ____ ___  ____ | |__ _  ____ _   _  ____ _ ____   ____ ___ ___ _   _  ___| |_  ____ ____  
| |// | |    / |___) ___) _ \|  _ \|  __) |/ _  | | | |/ ___) |  _ \ / _  (___)___) | | |/___)  _)/ _  )    \ 
|  /__| |   / /   ( (__| |_| | | | | |  | ( ( | | |_| | |   | | | | ( ( | |  |___ | |_| |___ | |_( (/ /| | | |
 \_____/   (_/     \____)___/|_| |_|_|  |_|\_|| |\____|_|   |_|_| |_|\_|| |  (___/ \__  (___/ \___)____)_|_|_|
                                          (_____|                   (_____|       (____/                      
______________________________________________________________________________________________________________
'

# sets mount points
cat <<EOF >/etc/fstab
# <fs> <mountpoint> <type> <opts> <dump> <pass>
# boot partition
${THIS_DEVICE}${THIS_DEVICE_SEPARATOR}1 /efi vfat umask=0077 0 2
# swap partition
${THIS_DEVICE}${THIS_DEVICE_SEPARATOR}2 none swap sw 0 0
# root partition
${THIS_DEVICE}${THIS_DEVICE_SEPARATOR}3 / ext4 defaults,noatime 0 1
EOF

# sets local network
echo ${THIS_HOST} >/etc/hostname
cat <<EOF >/etc/hosts
# IPv4 and IPv6 localhost aliases
127.0.0.1       localhost ${THIS_HOST}
::1             localhost ${THIS_HOST}
EOF

# sets root password
passwd <<EOF
${THIS_PASSWORD}
${THIS_PASSWORD}
EOF

# sets keymap
sed -i "s/keymap=\"us\"/keymap=\"${THIS_KEYMAP}\"/g" /etc/conf.d/keymaps

# removes useless ttys
sed -i 's/^c[3-6]:/#\0/' /etc/inittab
sed -i "s/^c1:12345:respawn:\/sbin\/agetty/\0 -a ${THIS_USER}/" /etc/inittab

# updates system environment variables
env-update && source /etc/profile && export PS1="(chroot) ${PS1}"

# installs networkmanager
emerge --ask=n net-misc/networkmanager || exit 1
rc-update add NetworkManager default

# installs doas
echo 'app-admin/doas persist' >>/etc/portage/package.use
emerge --ask=n app-admin/doas || exit 1
cat <<EOF >/etc/doas.conf
# https://wiki.gentoo.org/wiki/Doas
permit  persist :wheel
EOF
chown -c root:root /etc/doas.conf

# sets user
useradd -m -G users,wheel,audio,video,usb,plugdev -s /bin/bash ${THIS_USER}
chown -R -c ${THIS_USER}:${THIS_USER} /home/${THIS_USER}
passwd ${THIS_USER} <<EOF
${THIS_PASSWORD}
${THIS_PASSWORD}
EOF
passwd -dl root
