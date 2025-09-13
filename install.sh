#!/bin/bash

LATEST_METADATA='https://distfiles.gentoo.org/releases/amd64/autobuilds/latest-stage3-amd64-openrc.txt'
LATEST_CHROOT_SCRIPT='https://raw.githubusercontent.com/pedro-pereira-dev/gentoo-installer/refs/heads/main/chroot.sh'
LATEST_INTERACTIVE_SCRIPT='https://raw.githubusercontent.com/pedro-pereira-dev/gentoo-installer/refs/heads/main/interactive.sh'

INTERACTIVE_SCRIPT=$(mktemp)
wget --output-document "${INTERACTIVE_SCRIPT}" --quiet "${LATEST_INTERACTIVE_SCRIPT}" || exit 1
# shellcheck source=/dev/null
source "${INTERACTIVE_SCRIPT}"
rm "${INTERACTIVE_SCRIPT}"

if [ -d /sys/firmware/efi ]; then
  BOOT_FS='fat -F 32'
  BOOT_MOUNT='/mnt/efi'
  BOOT_PLATFORM='efi-64'
else
  BOOT_FS='ext4'
  BOOT_MOUNT='/mnt/boot'
  BOOT_PLATFORM='pc'
fi

yes | mkfs."${BOOT_FS}" "${SYSTEM_BOOT_DEVICE}" # boot partition with FAT32 for UEFI and EXT4 for BIOS
yes | mkfs.ext4 "${SYSTEM_ROOT_DEVICE}"         # root partition with EXT4

mount --mkdir "${SYSTEM_ROOT_DEVICE}" /mnt
mount --mkdir "${SYSTEM_BOOT_DEVICE}" "${BOOT_MOUNT}"

LATEST_RELEASE=$(wget --output-document - --quiet "${LATEST_METADATA}")
LATEST_BUILD=$(grep --only-matching --extended-regexp '.*/stage3-amd64-openrc-[0-9]*T[0-9]*Z.tar.xz' <<<"${LATEST_RELEASE}")
LATEST_STAGE="https://distfiles.gentoo.org/releases/amd64/autobuilds/${LATEST_BUILD}"

wget --output-document /mnt/stage3-current.tar.xz "${LATEST_STAGE}" || exit 1
pv /mnt/stage3-current.tar.xz | tar --directory /mnt --extract --file - --numeric-owner --preserve-permissions --xattrs-include='*.*' --xz
mkdir --parents /mnt/etc/portage/{package.accept_keywords,package.env,package.license,package.mask,package.use}
cp /mnt/etc/portage/make.conf /mnt/etc/portage/make.conf.bak

AVAILABLE_RAM=$(($(free --giga | awk '/Mem:/ {print $2}') / 2))                           # RAM in GB divided by 2GB
AVAILABLE_THREADS=$(nproc)                                                                # number of threads
MAKE_OPTS_JOBS=$((AVAILABLE_RAM < AVAILABLE_THREADS ? AVAILABLE_RAM : AVAILABLE_THREADS)) # min(RAM / 2GB, number of threads)
MAKE_OPTS_JOBS=$((MAKE_OPTS_JOBS > 1 ? MAKE_OPTS_JOBS : 1))                               # max(make_opt_jobs, 1)
LOAD_AVERAGE_JOBS=$((MAKE_OPTS_JOBS + 1))                                                 # max number of jobs plus one for io
PORTAGE_JOBS=$(((MAKE_OPTS_JOBS + 1) / 2))                                                # ceiling of half max number of jobs

cat <<EOF >/mnt/etc/portage/make.conf
# these settings were set by the installation script
# please consult /etc/portage/make.conf.bak for the original configuration
COMMON_FLAGS="-march=native -pipe -O2"
RUSTFLAGS="\${RUSTFLAGS} -C target-cpu=native"
CFLAGS="\${COMMON_FLAGS}"
CXXFLAGS="\${COMMON_FLAGS}"
FCFLAGS="\${COMMON_FLAGS}"
FFLAGS="\${COMMON_FLAGS}"

# this quiets the fetching operations to reduce verbosity
FETCHCOMMAND="\${FETCHCOMMAND} -q"
RESUMECOMMAND="\${RESUMECOMMAND} -q"

# this sets the language of build output to english
# and system bootloader platform
LC_MESSAGES="C.utf8"
GRUB_PLATFORMS="${BOOT_PLATFORM}"

# this sets the computed default value for emerge jobs
# as well as defaulting to binaries
EMERGE_DEFAULT_OPTS="--ask --jobs ${PORTAGE_JOBS} --load-average ${LOAD_AVERAGE_JOBS} --quiet --verbose"
FEATURES="\${FEATURES} binpkg-request-signature getbinpkg"
MAKEOPTS="--jobs ${MAKE_OPTS_JOBS} --load-average ${LOAD_AVERAGE_JOBS}"
EOF

cp --dereference /etc/resolv.conf /mnt/etc/
mount --types proc /proc /mnt/proc
mount --rbind /sys /mnt/sys
mount --make-rslave /mnt/sys
mount --rbind /dev /mnt/dev
mount --make-rslave /mnt/dev
mount --bind /run /mnt/run
mount --make-slave /mnt/run

CHROOT_SCRIPT=$(mktemp)
wget --output-document "${CHROOT_SCRIPT}" --quiet "${LATEST_CHROOT_SCRIPT}" || exit 1
sed \
  --expression="s|{{SYSTEM_HOSTNAME}}|${SYSTEM_HOSTNAME}|g" \
  --expression="s|{{SYSTEM_PASSWORD}}|${SYSTEM_PASSWORD}|g" \
  --expression="s|{{SYSTEM_BOOT_DEVICE}}|${SYSTEM_BOOT_DEVICE}|g" \
  --expression="s|{{SYSTEM_ROOT_DEVICE}}|${SYSTEM_ROOT_DEVICE}|g" \
  --expression="s|{{SYSTEM_KEYMAP}}|${SYSTEM_KEYMAP}|g" \
  --expression="s|{{SYSTEM_TIMEZONE}}|${SYSTEM_TIMEZONE}|g" \
  "${CHROOT_SCRIPT}" >/mnt/chroot.sh
rm "${CHROOT_SCRIPT}"

chroot /mnt /bin/bash <<EOF
env-update && source /etc/profile
source /chroot.sh
rm /chroot.sh /stage3-current.tar.xz
EOF
