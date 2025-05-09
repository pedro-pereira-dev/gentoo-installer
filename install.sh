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
SWAP_SIZE=${SWAP_SIZE:-'+8G'}
ROOT_SIZE=${ROOT_SIZE:-'" "'}

TIMEZONE=${TIMEZONE:-'Europe/Lisbon'}
KEYMAP=${KEYMAP:-'pt-latin9'}

LATEST_RELEASE=$(wget --output-document=- --quiet "${LATEST_METADATA}")
LATEST_BUILD=$(grep --only-matching --extended-regexp '.*/stage3-amd64-openrc-[0-9]*T[0-9]*Z.tar.xz' <<<"${LATEST_RELEASE}")
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

All data from disk ${DISK_DEVICE} will be erased!"
read -r -p 'Do you want to continue? (Y/n): ' CONFIRMATION && echo ''
[[ ${CONFIRMATION} == 'n' || ${THIS_CONFIRMATION} == 'N' ]] && exit 0

read -ra ALL_PARTITIONS <<<"$(blkid | grep -oE "${DISK_DEVICE}${DISK_PARTITION_SEPARATOR}\\w*" | xargs)"
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
fatlabel "${DISK_DEVICE}${DISK_PARTITION_SEPARATOR}1" ESP

swapon "${DISK_DEVICE}${DISK_PARTITION_SEPARATOR}2"
mount --mkdir "${DISK_DEVICE}${DISK_PARTITION_SEPARATOR}3" /mnt
mount --mkdir "${DISK_DEVICE}${DISK_PARTITION_SEPARATOR}1" /mnt/boot/efi

chronyd -q
cd /mnt || exit 1
wget "${LATEST_STAGE}" || exit 1
tar fpx stage3-*.tar.xz --directory='/mnt' --numeric-owner --xattrs-include='*.*'

rm --force --recursive /mnt/etc/portage/package.*
touch /mnt/etc/portage/{package.accept_keywords,package.license,package.mask,package.use}
cat <<'EOF' >/mnt/etc/portage/make.conf
# architecture support
COMMON_FLAGS="-march=native -O2 -pipe"
RUSTFLAGS="${RUSTFLAGS} -C target-cpu=native"

CFLAGS="${COMMON_FLAGS}"
CXXFLAGS="${COMMON_FLAGS}"
FCFLAGS="${COMMON_FLAGS}"
FFLAGS="${COMMON_FLAGS}"

# quiet data fetch
FETCHCOMMAND="${FETCHCOMMAND} --quiet"
RESUMECOMMAND="${RESUMECOMMAND} --quiet"

GRUB_PLATFORMS="efi-64"
LC_MESSAGES=C.utf8

# binaries support
FEATURES="${FEATURES} binpkg-request-signature getbinpkg"
EMERGE_DEFAULT_OPTS="--ask --verbose --quiet"
EOF

AVAILABLE_RAM=$((($(free | awk '/Mem:/ {print $7}') / (1024 * 1024) + 1) / 2))
AVAILABLE_THREADS=$(($(nproc) + 1))
MAKE_OPTS_JOBS=$((AVAILABLE_RAM < AVAILABLE_THREADS ? AVAILABLE_RAM : AVAILABLE_THREADS))
cat <<EOF >>/mnt/etc/portage/make.conf

# WIP: other optimizations could be tmpfs of portage in zram, ccache and binhost
# computed values based on ram and threads
EMERGE_DEFAULT_OPTS="\${EMERGE_DEFAULT_OPTS} --jobs $(awk '{print int(($1 + 1) / 2)}' <<<${MAKE_OPTS_JOBS}) --load-average $(("${MAKE_OPTS_JOBS}" + 1))"
MAKEOPTS="--jobs ${MAKE_OPTS_JOBS} --load-average $(("${MAKE_OPTS_JOBS}" + 1))"
EOF

cp --dereference /etc/resolv.conf /mnt/etc/
mount --types proc /proc /mnt/proc
mount --rbind /sys /mnt/sys
mount --make-rslave /mnt/sys
mount --rbind /dev /mnt/dev
mount --make-rslave /mnt/dev
mount --bind /run /mnt/run
mount --make-slave /mnt/run

export DISK_DEVICE DISK_PARTITION_SEPARATOR TIMEZONE SYSTEM_HOSTNAME PASSWORD KEYMAP
CHROOT_SCRIPT=$(mktemp)
wget --output-document=- --quiet "${LATEST_CHROOT_SCRIPT}" >"${CHROOT_SCRIPT}" || exit 1
{ eval "echo \"$(sed 's/"/\\"/g')\""; } <"${CHROOT_SCRIPT}" >/mnt/chroot.sh
rm --force "${CHROOT_SCRIPT}"

chroot /mnt /bin/bash <<'EOF'
env-update && source /etc/profile
source /chroot.sh
rm --force /chroot.sh
rm --force /stage3-*.tar.*
EOF
