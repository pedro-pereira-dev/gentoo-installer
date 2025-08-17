#!/bin/bash

LATEST_METADATA='https://distfiles.gentoo.org/releases/amd64/autobuilds/latest-stage3-amd64-openrc.txt'
LATEST_CHROOT_SCRIPT='https://raw.githubusercontent.com/pedro-pereira-dev/gentoo-installer/refs/heads/main/chroot.sh'
LATEST_INTERACTIVE_SCRIPT='https://raw.githubusercontent.com/pedro-pereira-dev/gentoo-installer/refs/heads/main/interactive.sh'

INTERACTIVE_SCRIPT=$(mktemp)
wget --output-document="${INTERACTIVE_SCRIPT}" --quiet "${LATEST_INTERACTIVE_SCRIPT}" || exit 1
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

LATEST_RELEASE=$(wget --output-document=- --quiet "${LATEST_METADATA}")
LATEST_BUILD=$(grep --only-matching --extended-regexp '.*/stage3-amd64-openrc-[0-9]*T[0-9]*Z.tar.xz' <<<"${LATEST_RELEASE}")
LATEST_STAGE="https://distfiles.gentoo.org/releases/amd64/autobuilds/${LATEST_BUILD}"

wget --output-document=/mnt/stage3-current.tar.xz --quiet "${LATEST_STAGE}" || exit 1
tar fpx /mnt/stage3-current.tar.xz --directory='/mnt' --numeric-owner --xattrs-include='*.*'

rm --force --recursive /mnt/etc/portage/package.*
touch /mnt/etc/portage/{package.accept_keywords,package.license,package.mask,package.use}

AVAILABLE_RAM=$((($(free | awk '/Mem:/ {print $7}') / (1024 * 1024)) / 2))                # RAM in GB divided by 2GB
AVAILABLE_THREADS=$(nproc)                                                                # number of threads
MAKE_OPTS_JOBS=$((AVAILABLE_RAM < AVAILABLE_THREADS ? AVAILABLE_RAM : AVAILABLE_THREADS)) # min(RAM / 2GB, number of threads)
[[ $MAKE_OPTS_JOBS -lt 1 ]] && MAKE_OPTS_JOBS=1                                           # needs to be at least 1
PORTAGE_JOBS=$(awk '{print int(($1 + 1) / 2)}' <<<${MAKE_OPTS_JOBS})                      # ceiling of half max number of jobs
LOAD_AVERAGE_JOBS=$(("${MAKE_OPTS_JOBS}" + 1))                                            # sets the limit of concurrent number of jobs

cat <<EOF >/mnt/etc/portage/make.conf
# compiler flags
COMMON_FLAGS="-march=native -O2 -pipe"
RUSTFLAGS="\${RUSTFLAGS} -C target-cpu=native"

CFLAGS="\${COMMON_FLAGS}"
CXXFLAGS="\${COMMON_FLAGS}"
FCFLAGS="\${COMMON_FLAGS}"
FFLAGS="\${COMMON_FLAGS}"

# silent fetching
FETCHCOMMAND="\${FETCHCOMMAND} --quiet"
RESUMECOMMAND="\${RESUMECOMMAND} --quiet"

# binary packages as default
FEATURES="\${FEATURES} binpkg-request-signature getbinpkg"
EMERGE_DEFAULT_OPTS="--ask --verbose --quiet"

# computed defaults based on RAM and CPU threads
EMERGE_DEFAULT_OPTS="\${EMERGE_DEFAULT_OPTS} --jobs ${PORTAGE_JOBS} --load-average ${LOAD_AVERAGE_JOBS}"
MAKEOPTS="--jobs ${MAKE_OPTS_JOBS} --load-average ${LOAD_AVERAGE_JOBS}"

GRUB_PLATFORMS="${BOOT_PLATFORM}"
LC_MESSAGES=C.utf8
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
wget --output-document="${CHROOT_SCRIPT}" --quiet "${LATEST_CHROOT_SCRIPT}" || exit 1
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
eselect news read >/dev/null 2>&1
EOF
