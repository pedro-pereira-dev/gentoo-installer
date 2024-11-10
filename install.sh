#!/bin/bash

# checks arguments, prints usage and prepares variables
while [[ $# -gt 0 ]]; do
  case $1 in
  -h | --help) usage && exit 0 ;;
  --hostname) THIS_HOST=$2 ;; --username) THIS_USER=$2 ;;
  --device) THIS_DEVICE=$2 ;; --device-separator) THIS_DEVICE_SEPARATOR=$2 ;;
  --efi-size) THIS_EFI_SIZE=$2 ;; --swap-size) THIS_SWAP_SIZE=$2 ;; --root-size) THIS_ROOT_SIZE=$2 ;;
  --timezone) THIS_TIMEZONE=$2 ;; --keymap) THIS_KEYMAP=$2 ;;
  esac
  shift
  shift
done
if [[ -z ${THIS_HOST} || -z ${THIS_USER} ]]; then
  echo -e "Usage: $0 --hostname <hostname> --username <username>
          [--device <device>] [--device-separator <separator>]
          [--efi-size <size>] [--swap-size <size>] [--root-size <size>]
          [--timezone <timezone>] [--keymap <keymap>]"
  exit 1
fi

# reads password
echo 'Setting up system password:'
read -s -p ' - Password: ' THIS_PASSWORD && echo ''
read -s -p ' - Confirm password: ' THIS_PASSWORD_CONFIRMATION && echo ''
# checks that passwords match
[[ ${THIS_PASSWORD} != ${THIS_PASSWORD_CONFIRMATION} ]] && echo 'Passwords do not match' && exit 1

# sets default values
THIS_DEVICE=/dev/${THIS_DEVICE:-nvme0n1}
THIS_EFI_SIZE=${THIS_EFI_SIZE:-+1G}
THIS_SWAP_SIZE=${THIS_SWAP_SIZE:-+32G}
THIS_ROOT_SIZE=${THIS_ROOT_SIZE:-+64G}
THIS_TIMEZONE=${THIS_TIMEZONE:-Europe/Lisbon}
THIS_KEYMAP=${THIS_KEYMAP:-pt-latin9}

# gets current stage3 url
STAGE_BUILD=$(wget -qO- https://distfiles.gentoo.org/releases/amd64/autobuilds/latest-stage3-amd64-openrc.txt |
  grep -oE '.*/stage3-amd64-openrc-[0-9]*T[0-9]*Z.tar.xz')
THIS_STAGE_FILE="https://distfiles.gentoo.org/releases/amd64/autobuilds/${STAGE_BUILD}"

# checks user confirmation
echo -e "
Hostname: ${THIS_HOST}
Username: ${THIS_USER}
Password: ********
Device: ${THIS_DEVICE}
Device separator: ${THIS_DEVICE_SEPARATOR}
EFI size: ${THIS_EFI_SIZE}
SWAP size: ${THIS_SWAP_SIZE}
ROOT size: ${THIS_ROOT_SIZE}
Timezone: ${THIS_TIMEZONE}
Keymap: ${THIS_KEYMAP}
Stage3 file: ${THIS_STAGE_FILE}
"
read -p 'Do you want to continue? (Y/n): ' THIS_CONFIRMATION && echo ''
[[ ${THIS_CONFIRMATION} == 'n' || ${THIS_CONFIRMATION} == 'N' ]] && exit 0

# partitions disk, a blank line will send a return to fdisk
sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' <<EOF | fdisk ${THIS_DEVICE}
    g  # create empty GPT partition table
    n  # create EFI partition
    # choose default partition number
    # choose default sector number
    ${THIS_EFI_SIZE}
    t  # create EFI partition type
    1  # EFI system type
    n  # create SWAP partition
    # choose default partition number
    # choose default sector number
    ${THIS_SWAP_SIZE}
    t  # create SWAP partition type
    # choose default partition number
    19 # Linux swap type
    n  # create ROOT partition
    # choose default partition number
    # choose default sector number
    ${THIS_ROOT_SIZE}
    t  # create ROOT partition type
    # choose default partition number
    23 # Linux root (x86-64) type
    p  # print partition table
    w  # write changes to disk
EOF

# creates filesystems
mkfs.vfat -F 32 ${THIS_DEVICE}${THIS_DEVICE_SEPARATOR}1 # fat32 BOOT
swapon ${THIS_DEVICE}${THIS_DEVICE_SEPARATOR}2          # activates swap
mkfs.ext4 ${THIS_DEVICE}${THIS_DEVICE_SEPARATOR}3 <<EOF
y
EOF

# mounts root partition
mkdir -p /mnt/gentoo && mount ${THIS_DEVICE}${THIS_DEVICE_SEPARATOR}3 /mnt/gentoo
cd /mnt/gentoo

# downloads stage file
wget ${THIS_STAGE_FILE} || exit 1
tar xpf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner

# configures default portage configuration
rm -rf /mnt/gentoo/etc/portage/package.*
touch /mnt/gentoo/etc/portage/{package.license,package.use}
cat <<EOF >/mnt/gentoo/etc/portage/make.conf
# global USE flags
USE="dbus"

# CPU settings
CPU_FLAGS_X86=""
# GPU settings
VIDEO_CARDS=""
# Input settings
INPUT_DEVICES=""

# portage default options
#MAKEOPTS="-jXX -lYY"
EMERGE_DEFAULT_OPTS="--ask --verbose --quiet-build"
FEATURES="getbinpkg binpkg-request-signature"

# compiler settings
COMMON_FLAGS="-march=native -O2 -pipe"
CFLAGS="\${COMMON_FLAGS}"
CXXFLAGS="\${COMMON_FLAGS}"
FCFLAGS="\${COMMON_FLAGS}"
FFLAGS="\${COMMON_FLAGS}"

# GRUB EFI settings
GRUB_PLATFORMS="efi-64"
# default build output language
LC_MESSAGES=C.utf8
EOF

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

# exports all variables
export THIS_HOST THIS_USER THIS_PASSWORD THIS_DEVICE THIS_DEVICE_SEPARATOR THIS_TIMEZONE THIS_KEYMAP
# creates chroot script from wget
THIS_CHROOT_SCRIPT=$(mktemp)
wget -qO- https://raw.githubusercontent.com/pedro-pereira-dev/gentoo-installer/refs/heads/main/chroot.sh >${THIS_CHROOT_SCRIPT} || exit 1
envsubst <${THIS_CHROOT_SCRIPT} >/mnt/gentoo/chroot.sh
rm -f ${THIS_CHROOT_SCRIPT}

# chroots into system
chroot /mnt/gentoo /bin/bash <<EOF
source /etc/profile && export PS1="(chroot) \${PS1}"
source /chroot.sh

eselect news read 
emerge --ask=n --depclean

rm /stage3-*.tar.*
rm /chroot.sh
EOF
