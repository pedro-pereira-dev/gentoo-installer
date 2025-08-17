#!/bin/bash

emerge-webrsync
emerge --ask=n --backtrack=30 --deep --newuse --update --verbose --with-bdeps=y @world

ln --force --symbolic '/usr/share/zoneinfo/{{SYSTEM_TIMEZONE}}' /etc/localtime
sed --in-place 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/g' /etc/locale.gen
locale-gen
eselect locale set 4
sed --in-place 's/keymap="us"/keymap="{{SYSTEM_KEYMAP}}"/g' /etc/conf.d/keymaps

# shellcheck source=/dev/null
env-update && source /etc/profile

echo 'sys-kernel/installkernel dracut grub' >>/etc/portage/package.use
echo 'sys-kernel/linux-firmware @BINARY-REDISTRIBUTABLE' >>/etc/portage/package.license
emerge --ask=n sys-kernel/gentoo-kernel-bin sys-kernel/installkernel sys-kernel/linux-firmware
sed --in-place 's/.*GRUB_CMDLINE_LINUX_DEFAULT.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet"/g' /etc/default/grub
sed --in-place 's/.*GRUB_TIMEOUT.*/GRUB_TIMEOUT=1/g' /etc/default/grub

if [ -d /sys/firmware/efi ]; then
  GRUB_INSTALL='--efi-directory=/efi'
  GRUB_CONFIG='/efi/EFI/Gentoo/grub.cfg'
  BOOT_FSTAB='{{SYSTEM_BOOT_DEVICE}} /efi vfat defaults,noatime,nodev,noexec,nosuid,dmask=0077,fmask=0177 0 2'
else
  GRUB_INSTALL='{{SYSTEM_BOOT_DEVICE}}'
  GRUB_INSTALL="${GRUB_INSTALL%?}"
  GRUB_CONFIG='/boot/grub/grub.cfg'
  BOOT_FSTAB='{{SYSTEM_BOOT_DEVICE}} /boot ext4 defaults,noatime 0 2'
fi

grub-install "${GRUB_INSTALL}"
grub-mkconfig --output="${GRUB_CONFIG}"

cat <<EOF >/etc/fstab
# <fs> <mountpoint> <type> <opts> <dump> <pass>
${BOOT_FSTAB}
{{SYSTEM_ROOT_DEVICE}} / ext4 defaults,noatime 0 1
EOF

echo '{{SYSTEM_HOSTNAME}}' >/etc/hostname
sed --in-place 's/localhost/{{SYSTEM_HOSTNAME}}/g' /etc/conf.d/hostname
cat <<EOF >/etc/hosts
# IPv4 and IPv6 localhost aliases
127.0.0.1 {{SYSTEM_HOSTNAME}} localhost
::1       {{SYSTEM_HOSTNAME}} localhost
EOF

passwd <<EOF
{{SYSTEM_PASSWORD}}
{{SYSTEM_PASSWORD}}
EOF
