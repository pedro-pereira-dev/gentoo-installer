#!/bin/bash

emerge-webrsync
getuto
emerge --ask=n --verbose --update --newuse --deep --with-bdeps=y --backtrack=30 @world

ln -sf "../usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
sed -i 's/#en_US ISO-8859-1/en_US ISO-8859-1/g' /etc/locale.gen
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/g' /etc/locale.gen
sed -i 's/keymap="us"/keymap="'"${KEYMAP}"'"/g' /etc/conf.d/keymaps
locale-gen && eselect locale set 6
env-update && source /etc/profile

echo "${SYSTEM_HOSTNAME}" >/etc/hostname
echo 'sys-kernel/installkernel dracut grub' >>/etc/portage/package.use
echo 'sys-kernel/linux-firmware @BINARY-REDISTRIBUTABLE' >>/etc/portage/package.license
emerge --ask=n sys-kernel/linux-firmware sys-kernel/installkernel

sed -i 's/.*GRUB_CMDLINE_LINUX_DEFAULT.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet"/g' /etc/default/grub
grub-install --efi-directory=/efi
emerge --ask=n sys-kernel/gentoo-kernel

cat <<EOF >/etc/fstab
# <fs> <mountpoint> <type> <opts> <dump> <pass>
${DISK_DEVICE}${DISK_PARTITION_SEPARATOR}1 /efi vfat umask=0077 0 2
${DISK_DEVICE}${DISK_PARTITION_SEPARATOR}2 none swap sw 0 0
${DISK_DEVICE}${DISK_PARTITION_SEPARATOR}3 / ext4 defaults,noatime 0 1
EOF

echo "${SYSTEM_HOSTNAME}" >/etc/hostname
cat <<EOF >/etc/hosts
# IPv4 and IPv6 localhost aliases
127.0.0.1 ${SYSTEM_HOSTNAME} localhost
::1       ${SYSTEM_HOSTNAME} localhost
EOF

passwd <<EOF
${PASSWORD}
${PASSWORD}
EOF
