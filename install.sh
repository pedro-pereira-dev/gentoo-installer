#!/bin/bash

LATEST_CHROOT_SCRIPT='https://raw.githubusercontent.com/pedro-pereira-dev/gentoo-installer/refs/heads/artix/chroot.sh'

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

DISK_PARTITION_SEPARATOR=$([[ "${DISK_DEVICE}" == *"nvme"* ]] && echo 'p' || echo '')

EFI_SIZE=${EFI_SIZE:-'+1G'}
SWAP_SIZE=${SWAP_SIZE:-'+8G'}
ROOT_SIZE=${ROOT_SIZE:-'" "'}

TIMEZONE=${TIMEZONE:-'Europe/Lisbon'}
KEYMAP=${KEYMAP:-'pt-latin9'}

echo -e "
Hostname: ${SYSTEM_HOSTNAME}
Partitions: ${DISK_DEVICE}${DISK_PARTITION_SEPARATOR}...
EFI size: ${EFI_SIZE}
SWAP size: ${SWAP_SIZE}
ROOT size: ${ROOT_SIZE}
Timezone: ${TIMEZONE}
Keymap: ${KEYMAP}

All data from disk ${DISK_DEVICE} will be erased!"
read -r -p 'Do you want to continue? (Y/n): ' CONFIRMATION && echo ''
[[ ${CONFIRMATION} == 'n' || ${THIS_CONFIRMATION} == 'N' ]] && exit 0

read -r -a ALL_PARTITIONS <<<"$(blkid | grep -oE "${DISK_DEVICE}${DISK_PARTITION_SEPARATOR}\\w*" | xargs)"
yes | wipefs --all "${ALL_PARTITIONS[@]}" "${DISK_DEVICE}"
sed --expression='s/\s*\([\+0-9a-zA-Z]*\).*/\1/' <<EOF | fdisk "${DISK_DEVICE}"
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

yes | mkfs.fat -F 32 "${DISK_DEVICE}${DISK_PARTITION_SEPARATOR}1" # fat32 BOOT
yes | mkswap "${DISK_DEVICE}${DISK_PARTITION_SEPARATOR}2"         # swap SWAP
yes | mkfs.ext4 "${DISK_DEVICE}${DISK_PARTITION_SEPARATOR}3"      # ext4 ROOT

swapon "${DISK_DEVICE}${DISK_PARTITION_SEPARATOR}2"
mount --mkdir "${DISK_DEVICE}${DISK_PARTITION_SEPARATOR}3" /mnt
mount --mkdir "${DISK_DEVICE}${DISK_PARTITION_SEPARATOR}1" /mnt/boot

dinitctl start ntpd
basestrap /mnt base connman-dinit dinit efibootmgr elogind-dinit grub linux linux-firmware
fstabgen -U /mnt >>/mnt/etc/fstab

export DISK_DEVICE DISK_PARTITION_SEPARATOR TIMEZONE SYSTEM_HOSTNAME PASSWORD KEYMAP
CHROOT_SCRIPT=$(mktemp)
wget --output-document=- --quiet "${LATEST_CHROOT_SCRIPT}" >"${CHROOT_SCRIPT}" || exit 1
{ eval "echo \"$(sed 's/"/\\"/g')\""; } <"${CHROOT_SCRIPT}" >/mnt/chroot.sh
rm "${CHROOT_SCRIPT}"

artix-chroot /mnt <<'EOF'
source /chroot.sh
rm /chroot.sh
EOF
