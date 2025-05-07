#!/bin/bash

emerge-webrsync
emerge --ask=n --backtrack=30 --deep --newuse --update --verbose --with-bdeps=y @world

sed --in-place 's/keymap="us"/keymap="'"${KEYMAP}"'"/g' /etc/conf.d/keymaps
ln --force --symbolic "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
hwclock --systohc
sed --in-place 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/g' /etc/locale.gen
locale-gen
eselect locale set 4
env-update && source /etc/profile

echo 'sys-kernel/installkernel dracut grub' >>/etc/portage/package.use
echo 'sys-kernel/linux-firmware @BINARY-REDISTRIBUTABLE' >>/etc/portage/package.license
emerge --ask=n sys-kernel/installkernel sys-kernel/linux-firmware

mkdir --parents /boot/efi
sed --in-place 's/.*GRUB_CMDLINE_LINUX_DEFAULT.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet"/g' /etc/default/grub
sed --in-place 's/.*GRUB_TIMEOUT.*/GRUB_TIMEOUT=1/g' /etc/default/grub
grub-install --bootloader-id='Gentoo Grub' --efi-directory=/boot/efi --target=x86_64-efi
emerge --ask=n sys-kernel/gentoo-kernel-bin

cat <<EOF >/etc/fstab
# <fs> <mountpoint> <type> <opts> <dump> <pass>
${DISK_DEVICE}${DISK_PARTITION_SEPARATOR}1 /boot vfat defaults,nodev,nosuid,noexec,fmask=0177,dmask=0077 0 2
${DISK_DEVICE}${DISK_PARTITION_SEPARATOR}2 none swap sw 0 0
${DISK_DEVICE}${DISK_PARTITION_SEPARATOR}3 / ext4 defaults 0 1
EOF

passwd <<EOF
${PASSWORD}
${PASSWORD}
EOF

echo "${SYSTEM_HOSTNAME}" >/etc/conf.d/hostname
echo "${SYSTEM_HOSTNAME}" >/etc/hostname
cat <<EOF >/etc/hosts
# IPv4 and IPv6 localhost aliases
127.0.0.1 ${SYSTEM_HOSTNAME} localhost
::1       ${SYSTEM_HOSTNAME} localhost
EOF
