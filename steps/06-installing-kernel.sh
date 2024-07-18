#!/bin/bash

clear
echo -e '
  ______    __     _                      _ _ _                 _                            _ 
 / __   |  / /    (_)           _        | | (_)               | |                          | |
| | //| | / /_ ___ _ ____   ___| |_  ____| | |_ ____   ____ ___| |  _ ____  ____ ____   ____| |
| |// | |/ __ (___) |  _ \ /___)  _)/ _  | | | |  _ \ / _  (___) | / ) _  )/ ___)  _ \ / _  ) |
|  /__| ( (__) )  | | | | |___ | |_( ( | | | | | | | ( ( | |   | |< ( (/ /| |   | | | ( (/ /| |
 \_____/ \____/   |_|_| |_(___/ \___)_||_|_|_|_|_| |_|\_|| |   |_| \_)____)_|   |_| |_|\____)_|
                                                     (_____|                                   
_______________________________________________________________________________________________
'

# installs firmware, hooks, bootloader and kernel
echo 'sys-kernel/linux-firmware @BINARY-REDISTRIBUTABLE' >>/etc/portage/package.license
echo 'sys-kernel/installkernel dracut grub' >>/etc/portage/package.use
emerge --ask=n sys-kernel/linux-firmware sys-kernel/installkernel || exit 1
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id='Gentoo Grub Bootloader' || exit 1
sed -i 's/#GRUB_TIMEOUT=5/GRUB_TIMEOUT=0/g' /etc/default/grub
sed -i 's/#GRUB_CMDLINE_LINUX_DEFAULT=""/GRUB_CMDLINE_LINUX_DEFAULT="quiet"/g' /etc/default/grub
sed -i 's/#GRUB_DISABLE_SUBMENU=y/GRUB_DISABLE_SUBMENU=y/g' /etc/default/grub
echo -e '\n# Comment to enable OS prober feature warning' >>/etc/default/grub
echo 'GRUB_DISABLE_OS_PROBER=false' >>/etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg
emerge --ask=n sys-kernel/gentoo-kernel || exit 1
env-update && source /etc/profile && export PS1="(chroot) ${PS1}"
