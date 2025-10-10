#!/bin/bash
# shellcheck source=/dev/null

emerge-webrsync

ln -fs '/usr/share/zoneinfo/{{SYSTEM_TIMEZONE}}' /etc/localtime
echo 'en_US.UTF-8 UTF-8' >/etc/locale.gen
sed -i 's/keymap="us"/keymap="{{SYSTEM_KEYMAP}}"/g' /etc/conf.d/keymaps
locale-gen && eselect locale set 4
env-update && source /etc/profile

echo 'sys-kernel/installkernel dracut grub' >/etc/portage/package.use
echo 'sys-kernel/linux-firmware @BINARY-REDISTRIBUTABLE' >/etc/portage/package.license
emerge --ask=n sys-kernel/gentoo-kernel-bin sys-kernel/installkernel sys-kernel/linux-firmware
eselect news read >/dev/null 2>&1

is_aarch64() { test "$(uname -m)" = 'aarch64'; }
is_amd64() { test "$(uname -m)" = 'x86_64'; }

is_bios() { ! test -d '/sys/firmware/efi'; }
is_uefi() { test -d '/sys/firmware/efi'; }

is_bios && BOOT_FSTAB='{{SYSTEM_BOOT_DEVICE}} /boot ext4 defaults,noatime 0 2'
is_bios && GRUB_CONFIG='/boot/grub/grub.cfg'
is_bios && GRUB_INSTALL='{{SYSTEM_BOOT_DEVICE}}'
is_bios && GRUB_INSTALL="${GRUB_INSTALL%?}" # removes last character

is_uefi && BOOT_FSTAB='{{SYSTEM_BOOT_DEVICE}} /efi vfat defaults,noatime,nodev,noexec,nosuid,dmask=0077,fmask=0177 0 2'
is_uefi && is_aarch64 && GRUB_CONFIG='/efi/EFI/gentoo/grubaa64.cfg'
is_uefi && is_amd64 && GRUB_CONFIG='/efi/EFI/gentoo/grub.cfg'
is_uefi && GRUB_INSTALL='--efi-directory=/efi'

grub-install "$GRUB_INSTALL"
grub-mkconfig -o "$GRUB_CONFIG"

echo '{{SYSTEM_HOSTNAME}}' >/etc/hostname
cat <<EOF >/etc/fstab
# <fs> <mountpoint> <type> <opts> <dump> <pass>
${BOOT_FSTAB}
{{SYSTEM_ROOT_DEVICE}} / ext4 defaults,noatime 0 1
EOF

passwd <<EOF
{{SYSTEM_PASSWORD}}
{{SYSTEM_PASSWORD}}
EOF
