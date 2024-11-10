#!/bin/bash

# mounts boot partition
mkdir -p /efi && mount ${THIS_DEVICE}${THIS_DEVICE_SEPARATOR}1 /efi

# installs base system
emerge-webrsync && getuto
emerge --oneshot --ask=n app-portage/cpuid2cpuflags
sed -i "s/CPU_FLAGS_X86=\"\"/CPU_FLAGS_X86=\"$(cpuid2cpuflags | cut -d' ' -f2-)\"/g" /etc/portage/make.conf
emerge --ask=n --verbose --update --newuse --deep --with-bdeps=y --backtrack=30 @world

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
# sets hostname
echo ${THIS_HOST} >/etc/hostname
cat <<EOF >/etc/hosts
# IPv4 and IPv6 localhost aliases
127.0.0.1 localhost ${THIS_HOST}
::1       localhost ${THIS_HOST}
EOF
# sets timezone
echo ${THIS_TIMEZONE} >/etc/timezone
emerge --ask=n --config sys-libs/timezone-data
# sets keymap
sed -i "s/keymap=\"us\"/keymap=\"${THIS_KEYMAP}\"/g" /etc/conf.d/keymaps
# sets locale
sed -i 's/#en_US ISO-8859-1/en_US ISO-8859-1/g' /etc/locale.gen
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/g' /etc/locale.gen
locale-gen
eselect locale set 6
env-update && source /etc/profile && export PS1="(chroot) ${PS1}"

# installs firmware, hooks and bootloader
echo 'sys-kernel/linux-firmware @BINARY-REDISTRIBUTABLE' >>/etc/portage/package.license
echo 'sys-kernel/installkernel dracut grub' >>/etc/portage/package.use
emerge --ask=n sys-kernel/linux-firmware sys-kernel/installkernel || exit 1
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id='Gentoo Grub Bootloader' || exit 1
# installs kernel and dependencies
echo 'app-admin/doas persist' >>/etc/portage/package.use
emerge --ask=n sys-kernel/gentoo-kernel net-misc/networkmanager app-admin/doas || exit 1
rc-update add NetworkManager default
cat <<EOF >/etc/doas.conf
permit persist :wheel
permit nopass  :wheel as root cmd reboot
permit nopass  :wheel as root cmd shutdown
EOF
chown -c root:root /etc/doas.conf

# sets superuser
passwd -dl root
useradd -m -G users,wheel,audio,video,usb,plugdev -s /bin/bash ${THIS_USER}
chown -R -c ${THIS_USER}:${THIS_USER} /home/${THIS_USER}
passwd ${THIS_USER} <<EOF
${THIS_PASSWORD}
${THIS_PASSWORD}
EOF
