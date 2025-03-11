#!/bin/bash

LATEST_METADATA='https://distfiles.gentoo.org/releases/amd64/autobuilds/latest-stage3-amd64-openrc.txt'
LATEST_CHROOT_SCRIPT='https://raw.githubusercontent.com/pedro-pereira-dev/gentoo-installer/refs/heads/main/chroot.sh'

function usage() {
  echo -e "\nUsage: $(basename "$0")
  --hostname <hostname> [--timezone <timezone>] [--keymap <keymap>]
  --disk <device> [--efi-size <size>] [--swap-size <size>] [--root-size <size>]
  [--password <password>]\n"
}

while [[ $# -gt 0 ]]; do
  case $1 in
  -h | --help) usage && exit 0 ;;
  --hostname) SYSTEM_HOSTNAME=$2 ;;
  --timezone) TIMEZONE=$2 ;; --keymap) KEYMAP=$2 ;;
  --disk) DISK_DEVICE=$2 ;;
  --efi-size) EFI_SIZE=$2 ;; --swap-size) SWAP_SIZE=$2 ;; --root-size) ROOT_SIZE=$2 ;;
  --password) PASSWORD=$2 ;;
  esac
  shift
  shift
done

[[ -z ${SYSTEM_HOSTNAME} || -z ${DISK_DEVICE} ]] && usage && exit 1

if [[ -z ${PASSWORD} ]]; then
  while true; do
    echo -e "\nSetting up system password:"
    read -r -s -p ' - Password: ' PASSWORD && echo ''
    read -r -s -p ' - Confirm password: ' PASSWORD_CONFIRMATION && echo ''
    [[ "${PASSWORD}" == "${PASSWORD_CONFIRMATION}" ]] && echo '' && break
    echo -e '\nPasswords do not match!'
  done
fi

DISK_DEVICE=${DISK_DEVICE:-/dev/nvme0n1}
DISK_PARTITION_SEPARATOR=$([[ "${DISK_DEVICE}" == *"nvme"* ]] && echo 'p' || echo '')

EFI_SIZE=${EFI_SIZE:-'+1G'}
SWAP_SIZE=${SWAP_SIZE:-'+4G'}
ROOT_SIZE=${ROOT_SIZE:-'" "'}

TIMEZONE=${TIMEZONE:-'Europe/Lisbon'}
KEYMAP=${KEYMAP:-'pt-latin9'}

LATEST_RELEASE=$(wget -qO- "${LATEST_METADATA}")
LATEST_BUILD=$(grep -oE '.*/stage3-amd64-openrc-[0-9]*T[0-9]*Z.tar.xz' <<<"${LATEST_RELEASE}")
LATEST_STAGE="https://distfiles.gentoo.org/releases/amd64/autobuilds/${LATEST_BUILD}"

echo -e "
Hostname: ${SYSTEM_HOSTNAME}
Partitions: ${DISK_DEVICE}${DISK_PARTITION_SEPARATOR}...
EFI size: ${EFI_SIZE}
SWAP size: ${SWAP_SIZE}
ROOT size: ${ROOT_SIZE}
Timezone: ${TIMEZONE}
Keymap: ${KEYMAP}
Stage3 file: ${LATEST_STAGE}

All data from disk ${DISK_DEVICE}${DISK_PARTITION_SEPARATOR} will be erased!"
read -r -p 'Do you want to continue? (Y/n): ' CONFIRMATION && echo ''
[[ ${CONFIRMATION} == 'n' || ${THIS_CONFIRMATION} == 'N' ]] && exit 0

read -ra ALL_PARTITIONS <<<"$(blkid | grep -oE "${DISK_DEVICE}${DISK_PARTITION_SEPARATOR}\\w*" | xargs)"
wipefs -a "${ALL_PARTITIONS[@]}" "${DISK_DEVICE}${DISK_PARTITION_SEPARATOR}"
sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' <<EOF | fdisk "${DISK_DEVICE}"
    g  # create empty GPT partition table
    n  # create EFI partition
    # choose default partition number
    # choose default sector number
    ${EFI_SIZE}
    t  # create EFI partition type
    1  # EFI system type
    n  # create SWAP partition
    # choose default partition number
    # choose default sector number
    ${SWAP_SIZE}
    t  # create SWAP partition type
    # choose default partition number
    19 # Linux swap type
    n  # create ROOT partition
    # choose default partition number
    # choose default sector number
    ${ROOT_SIZE}
    t  # create ROOT partition type
    # choose default partition number
    23 # Linux root (x86-64) type
    p  # print partition table
    w  # write changes to disk
EOF

mkfs.vfat -F 32 "${DISK_DEVICE}${DISK_PARTITION_SEPARATOR}1" # fat32 BOOT
mkswap "${DISK_DEVICE}${DISK_PARTITION_SEPARATOR}2"          # swap SWAP
swapon "${DISK_DEVICE}${DISK_PARTITION_SEPARATOR}2"          # activates swap
mkfs.ext4 "${DISK_DEVICE}${DISK_PARTITION_SEPARATOR}3"       # ext4 ROOT

mkdir -p /mnt/gentoo
mount "${DISK_DEVICE}${DISK_PARTITION_SEPARATOR}3" /mnt/gentoo
cd /mnt/gentoo || exit 1

chronyd -q
wget "${LATEST_STAGE}" || exit 1
tar xpf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner -C /mnt/gentoo

rm -rf /mnt/gentoo/etc/portage/package.*
touch /mnt/gentoo/etc/portage/{package.license,package.use}
cat <<'EOF' >/mnt/gentoo/etc/portage/make.conf
USE=""

#CPU_FLAGS_X86=""
#VIDEO_CARDS=""
#INPUT_DEVICES=""

#MAKEOPTS="-j[X] -l[X+1]" # X = min(RAM/2GB, threads)
EMERGE_DEFAULT_OPTS="--ask --verbose --quiet-build"
FEATURES="getbinpkg binpkg-request-signature"

COMMON_FLAGS="-march=native -O2 -pipe"
CFLAGS="${COMMON_FLAGS}"
CXXFLAGS="${COMMON_FLAGS}"
RUSTFLAGS="${RUSTFLAGS} -C target-cpu=native"
GRUB_PLATFORMS="efi-64"
LC_MESSAGES=C.utf8
EOF

cp --dereference /etc/resolv.conf /mnt/gentoo/etc/
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run
mount --make-slave /mnt/gentoo/run

export DISK_DEVICE DISK_PARTITION_SEPARATOR TIMEZONE SYSTEM_HOSTNAME PASSWORD KEYMAP
CHROOT_SCRIPT=$(mktemp)
wget -qO- "${LATEST_CHROOT_SCRIPT}" >"${CHROOT_SCRIPT}" || exit 1
{ eval "echo \"$(sed 's/"/\\"/g')\""; } <"${CHROOT_SCRIPT}" >/mnt/gentoo/chroot.sh
rm -f "${CHROOT_SCRIPT}"

chroot /mnt/gentoo /bin/bash <<'EOF'
env-update && source /etc/profile
source /chroot.sh
rm /chroot.sh
rm /stage3-*.tar.*
EOF
