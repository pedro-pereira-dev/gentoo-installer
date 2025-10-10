#!/bin/sh

LATEST_CHROOT_SCRIPT='https://raw.githubusercontent.com/pedro-pereira-dev/gentoo-installer/refs/heads/main/chroot.sh'

is_aarch64() { test "$(uname -m)" = 'aarch64'; }
is_amd64() { test "$(uname -m)" = 'x86_64'; }

is_bios() { ! test -d '/sys/firmware/efi'; }
is_uefi() { test -d '/sys/firmware/efi'; }

is_aarch64 && _ARCH='arm64'
is_amd64 && _ARCH='amd64'

LATEST_METADATA="https://distfiles.gentoo.org/releases/$_ARCH/autobuilds/current-install-$_ARCH-minimal/latest-install-$_ARCH-minimal.txt"
LATEST_BUILD=$(curl -Lfs "$LATEST_METADATA" | sed -n '6p' | cut -d' ' -f1)
LATEST_STAGE="https://distfiles.gentoo.org/releases/$_ARCH/autobuilds/current-install-$_ARCH-minimal/$LATEST_BUILD"

while [ $# -gt 0 ]; do
  case "$1" in
  --hostname) SYSTEM_HOSTNAME=$2 ;; --password) SYSTEM_PASSWORD=$2 ;;
  --boot) SYSTEM_BOOT_DEVICE=$2 ;; --root) SYSTEM_ROOT_DEVICE=$2 ;;
  --keymap) SYSTEM_KEYMAP=$2 ;; --timezone) SYSTEM_TIMEZONE=$2 ;;
  esac
  shift && shift
done

test -z "$SYSTEM_HOSTNAME" && while true; do
  printf ' - System hostname: ' && read -r SYSTEM_HOSTNAME
  test -n "$SYSTEM_HOSTNAME" && case "$SYSTEM_HOSTNAME" in
  *[!a-zA-Z0-9-]* | '') ;;
  *) break ;;
  esac
done
test -z "$SYSTEM_PASSWORD" && while true; do
  printf ' - System password: ' && read -r SYSTEM_PASSWORD
  test -z "$SYSTEM_PASSWORD" && continue
  printf ' - Confirm system password: ' && read -r PASSWORD_CONFIRMATION
  test "$SYSTEM_PASSWORD" = "$PASSWORD_CONFIRMATION" && break
done

test -z "$SYSTEM_BOOT_DEVICE" && while true; do
  printf ' - System boot device:' && read -r SYSTEM_BOOT_DEVICE
  test -e "$SYSTEM_BOOT_DEVICE" && break
done
test -z "$SYSTEM_ROOT_DEVICE" && while true; do
  printf ' - System root device:' && read -r SYSTEM_ROOT_DEVICE
  test -e "$SYSTEM_ROOT_DEVICE" && break
done

test -z "$SYSTEM_TIMEZONE" &&
  printf ' - System timezone: [Europe/Lisbon] ' && read -r SYSTEM_TIMEZONE
SYSTEM_TIMEZONE=${SYSTEM_TIMEZONE:-'Europe/Lisbon'}
test -z "$SYSTEM_KEYMAP" &&
  printf ' - System keymap: [pt-latin9] ' && read -r SYSTEM_KEYMAP
SYSTEM_KEYMAP=${SYSTEM_KEYMAP:-'pt-latin9'}

printf 'Setup summary...\n'
printf ' - System hostname: %s\n' "$SYSTEM_HOSTNAME"
printf ' - System password: %s\n' "$SYSTEM_PASSWORD"
printf ' - System boot device: %s\n' "$SYSTEM_BOOT_DEVICE"
printf ' - System root device: %s\n' "$SYSTEM_ROOT_DEVICE"
printf ' - System timezone: %s\n' "$SYSTEM_TIMEZONE"
printf ' - System keymap: %s\n' "$SYSTEM_KEYMAP"
printf '\n'
printf 'All data from devices %s and %s will be erased!\n' "$SYSTEM_BOOT_DEVICE" "$SYSTEM_ROOT_DEVICE"
printf 'Do you want to continue? [Y/n]: ' && read -r CONFIRMATION
[ ! "$CONFIRMATION" = 'n' ] && [ ! "$THIS_CONFIRMATION" = 'N' ] || exit 0

is_bios && BOOT_FS='mkfs.ext4'
is_bios && BOOT_MOUNT='/mnt/boot'
is_bios && BOOT_PLATFORM='pc'

is_uefi && BOOT_FS='mkfs.fat -F 32'
is_uefi && BOOT_MOUNT='/mnt/efi'
is_uefi && BOOT_PLATFORM='efi-64'

yes | $BOOT_FS "$SYSTEM_BOOT_DEVICE"  # boot partition with FAT32 for UEFI and EXT4 for BIOS
yes | mkfs.ext4 "$SYSTEM_ROOT_DEVICE" # root partition with EXT4

mount -m "$SYSTEM_ROOT_DEVICE" /mnt
mount -m "$SYSTEM_BOOT_DEVICE" "$BOOT_MOUNT"

curl -Lf "$LATEST_STAGE" >/mnt/stage3-current.tar.xz
tar xpf /mnt/stage3-current.tar.xz -C /mnt --numeric-owner --xattrs-include='*.*'

exit 0

tar --directory /mnt --extract --file /mnt/stage3-current.tar.xz --numeric-owner --preserve-permissions --xattrs-include='*.*' --xz
rm -fr /mnt/etc/portage/package.*
cp /mnt/etc/portage/make.conf /mnt/etc/portage/make.conf.old

AVAILABLE_RAM=$(($(free --giga | awk '/Mem:/ {print $2}') / 2))                           # RAM in GB divided by 2GB
AVAILABLE_THREADS=$(nproc)                                                                # number of threads
MAKE_OPTS_JOBS=$((AVAILABLE_RAM < AVAILABLE_THREADS ? AVAILABLE_RAM : AVAILABLE_THREADS)) # min(RAM / 2GB, number of threads)
MAKE_OPTS_JOBS=$((MAKE_OPTS_JOBS > 1 ? MAKE_OPTS_JOBS : 1))                               # max(make_opt_jobs, 1)
LOAD_AVERAGE_JOBS=$((MAKE_OPTS_JOBS + 1))                                                 # max number of jobs plus one for io
PORTAGE_JOBS=$(((MAKE_OPTS_JOBS + 1) / 2))                                                # ceiling of half max number of jobs

cat <<EOF >/mnt/etc/portage/make.conf
# these settings were set by the installation script
# please consult /etc/portage/make.conf.bak for the original configuration
COMMON_FLAGS="-march=native -O2 -pipe"
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
GRUB_PLATFORMS="$BOOT_PLATFORM"

# this sets the computed default value for emerge jobs
# as well as defaulting to binaries
EMERGE_DEFAULT_OPTS="--ask --jobs $PORTAGE_JOBS --load-average $LOAD_AVERAGE_JOBS --quiet --verbose"
FEATURES="\${FEATURES} binpkg-request-signature getbinpkg"
MAKEOPTS="--jobs $MAKE_OPTS_JOBS --load-average $LOAD_AVERAGE_JOBS"
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
