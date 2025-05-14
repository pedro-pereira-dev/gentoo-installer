#!/bin/bash

emerge-webrsync
emerge --ask=n --backtrack=30 --deep --newuse --update --verbose --with-bdeps=y @world

hwclock --systohc
ln --force --symbolic "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
sed --in-place 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/g' /etc/locale.gen
locale-gen
eselect locale set 4
env-update && source /etc/profile

echo 'sys-kernel/installkernel dracut grub' >>/etc/portage/package.use
echo 'sys-kernel/linux-firmware @BINARY-REDISTRIBUTABLE' >>/etc/portage/package.license
emerge --ask=n net-misc/networkmanager sys-kernel/gentoo-kernel-bin sys-kernel/installkernel sys-kernel/linux-firmware
sed --in-place 's/.*GRUB_CMDLINE_LINUX_DEFAULT.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet"/g' /etc/default/grub
sed --in-place 's/.*GRUB_TIMEOUT.*/GRUB_TIMEOUT=1/g' /etc/default/grub
grub-install --efi-directory=/boot --removable --target=x86_64-efi
grub-mkconfig -o /boot/grub/grub.cfg

rc-update add NetworkManager default

sed --in-place 's/keymap="us"/keymap="'"${KEYMAP}"'"/g' /etc/conf.d/keymaps

cat <<EOF >/etc/fstab
# <fs> <mountpoint> <type> <opts> <dump> <pass>
${DISK_DEVICE}${DISK_PARTITION_SEPARATOR}1 /boot vfat defaults,nodev,nosuid,noexec,fmask=0177,dmask=0077 0 2
${DISK_DEVICE}${DISK_PARTITION_SEPARATOR}2 none swap sw 0 0
${DISK_DEVICE}${DISK_PARTITION_SEPARATOR}3 / ext4 defaults 0 1
EOF

echo "${SYSTEM_HOSTNAME}" >/etc/hostname
sed --in-place "s/localhost/${SYSTEM_HOSTNAME}/g" /etc/conf.d/hostname
cat <<EOF >/etc/hosts
# IPv4 and IPv6 localhost aliases
127.0.0.1 ${SYSTEM_HOSTNAME} localhost
::1       ${SYSTEM_HOSTNAME} localhost
EOF

passwd <<EOF
${PASSWORD}
${PASSWORD}
EOF
