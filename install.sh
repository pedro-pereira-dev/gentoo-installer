#!/bin/sh
# shellcheck disable=SC2016
set -eou pipefail

get_parameter() {
  _FLAG='' && [ $# -ge 1 ] && _FLAG=$1 && shift
  while [ $# -ge 1 ]; do
    _PARAM='' && [ $# -ge 1 ] && _PARAM=$1 && shift
    [ "$_FLAG" = "$_PARAM" ] && {
      _VAL='' && [ $# -ge 1 ] && _VAL=$1
      # prints if it does not start with -
      [ -n "$_VAL" ] && expr "x$_VAL" : 'x[^-]' >/dev/null && echo "$_VAL"
      return 0
    }
  done
  return 1
}

is_aarch64() { test "$(uname -m)" = aarch64; }
is_amd64() { test "$(uname -m)" = x86_64; }

is_bios() { ! is_uefi; }
is_uefi() { test -d /sys/firmware/efi; }

is_swap_enabled() { get_parameter --swap "$@" >/dev/null; }

_HOSTNAME=$(get_parameter --hostname "$@") && [ -n "$_HOSTNAME" ] ||
  while true; do
    printf 'Hostname: ' && read -r _HOSTNAME
    [ -n "$_HOSTNAME" ] && case $_HOSTNAME in
    *[!a-zA-Z0-9-]* | '') ;;
    *) break ;;
    esac
  done
_PASSWORD=$(get_parameter --password "$@") && [ -n "$_PASSWORD" ] ||
  while true; do
    printf 'Password: ' && read -r _PASSWORD
    [ -z "$_PASSWORD" ] && continue
    printf 'Confirm password: ' && read -r _PASSWORD_CONFIRMATION
    [ "$_PASSWORD" = "$_PASSWORD_CONFIRMATION" ] && break
  done

_BOOT_DEV=$(get_parameter --boot "$@") && [ -n "$_BOOT_DEV" ] ||
  while true; do
    printf 'Boot device:' && read -r _BOOT_DEV
    [ -e "$_BOOT_DEV" ] && break
  done
_ROOT_DEV=$(get_parameter --root "$@") && [ -n "$_ROOT_DEV" ] ||
  while true; do
    printf 'Root device:' && read -r _ROOT_DEV
    [ -e "$_ROOT_DEV" ] && break
  done

is_swap_enabled "$@" && {
  _SWAP_SIZE=$(get_parameter --swap "$@") && [ -z "$_SWAP_SIZE" ] &&
    printf 'Swap size: [4G] ' && read -r _SWAP_SIZE
  _SWAP_SIZE=${_SWAP_SIZE:-4G}
}
_KEYMAP=$(get_parameter --keymap "$@") && [ -z "$_KEYMAP" ] &&
  printf 'Keymap: [pt-latin9] ' && read -r _KEYMAP
_KEYMAP=${_KEYMAP:-pt-latin9}
_TIMEZONE=$(get_parameter --timezone "$@") && [ -z "$_TIMEZONE" ] &&
  printf 'Timezone: [Europe/Lisbon] ' && read -r _TIMEZONE
_TIMEZONE=${_TIMEZONE:-Europe/Lisbon}

echo 'Installation details:'
is_bios && echo ' - Partition table: msdos'
is_uefi && echo ' - Partition table: gpt'
echo " - CPU architecture: $(uname -m)"
echo " - Hostname: $_HOSTNAME"
echo " - Password: $_PASSWORD"
echo " - Boot device: $_BOOT_DEV"
echo " - Root device: $_ROOT_DEV"
is_swap_enabled "$@" && echo " - Swap file size: $_SWAP_SIZE"
echo " - Keymap: $_KEYMAP"
echo " - Timezone: $_TIMEZONE"
echo ''
echo "All data from devices $_BOOT_DEV and $_ROOT_DEV will be erased!"
printf 'Press any key to continue...' && read -r _

is_bios && ! mkfs.ext4 -F "$_BOOT_DEV" && exit 1   # mbr / bios partition with EXT4
is_uefi && ! mkfs.fat -F 32 "$_BOOT_DEV" && exit 1 # efi partition with FAT32
mkfs.ext4 -F "$_ROOT_DEV" || exit 1                # root partition with EXT4

mount -m "$_ROOT_DEV" /mnt || exit 1
is_bios && ! mount -m "$_BOOT_DEV" /mnt/boot && exit 1
is_uefi && ! mount -m "$_BOOT_DEV" /mnt/efi && exit 1

{ is_aarch64 && _ARCH=arm64; } || { is_amd64 && _ARCH=amd64; }
_METADATA="https://gentoo.osuosl.org/releases/$_ARCH/autobuilds/latest-stage3-$_ARCH-openrc.txt"
_BUILD=$(curl -Lfs "$_METADATA" | sed -n 6p | cut -d' ' -f1)
_STAGE_FILE="https://distfiles.gentoo.org/releases/$_ARCH/autobuilds/$_BUILD"

echo 'Dowloading latest gentoo stage release...'
curl -Lf# -o /mnt/stage3-current.tar.xz "$_STAGE_FILE" || exit 1
tar xpf /mnt/stage3-current.tar.xz -C /mnt --numeric-owner --xattrs-include=*.* || exit 1
rm -fr /mnt/stage3-current.tar.xz /mnt/etc/portage/package.*

cp -L /etc/resolv.conf /mnt/etc
mount --types proc /proc /mnt/proc
mount --rbind /sys /mnt/sys
mount --make-rslave /mnt/sys
mount --rbind /dev /mnt/dev
mount --make-rslave /mnt/dev
mount --bind /run /mnt/run
mount --make-slave /mnt/run

_THREADS=$(nproc)                               # number of threads
_TOTAL_RAM=$(free -g | awk '/Mem:/ {print $2}') # in gb
_HALF_RAM=$((_TOTAL_RAM / 2))                   # in gb

_MAKE_JOBS=$_THREADS
[ "$_HALF_RAM" -lt "$_THREADS" ] && _MAKE_JOBS=$_HALF_RAM # min between threads and available 2gb ram per thread
[ "$_MAKE_JOBS" -lt 1 ] && _MAKE_JOBS=1                   # must have at least one job
_LOAD_JOBS=$((_MAKE_JOBS + 1))                            # extra one io thread
_PORTAGE_JOBS=$((_LOAD_JOBS / 2))                         # allow half of jobs to portage

mkdir -p /mnt/etc/portage/env
echo '*/* gentoo-installer-make.conf' >>/mnt/etc/portage/package.env
{
  echo '# compiler flags targetting system'
  echo 'RUSTFLAGS="$RUSTFLAGS -C target-cpu=native"'
  echo 'COMMON_FLAGS="-march=native -O2 -pipe"'
  echo 'CFLAGS="$COMMON_FLAGS"'
  echo 'CXXFLAGS="$COMMON_FLAGS"'
  echo 'FCFLAGS="$COMMON_FLAGS"'
  echo 'FFLAGS="$COMMON_FLAGS"'
  echo ''
  echo '# quiet fetches'
  echo 'FETCHCOMMAND="$FETCHCOMMAND -q"'
  echo 'RESUMECOMMAND="$RESUMECOMMAND -q"'
  echo ''
  echo '# bootloader platform architecture'
  is_bios && echo 'GRUB_PLATFORMS="pc"'
  is_uefi && echo 'GRUB_PLATFORMS="efi-64"'
  echo ''
  echo '# portage default options'
  echo "EMERGE_DEFAULT_OPTS=\"--ask --jobs $_PORTAGE_JOBS --load-average $_LOAD_JOBS --quiet --verbose\""
  echo 'FEATURES="$FEATURES binpkg-request-signature getbinpkg"'
  echo "MAKEOPTS=\"--jobs $_MAKE_JOBS --load-average $_LOAD_JOBS\""
} >>/mnt/etc/portage/env/gentoo-installer-make.conf

chroot /mnt /bin/bash -c 'emerge-webrsync' || exit 1
chroot /mnt /bin/bash -c "ln -fs /usr/share/zoneinfo/$_TIMEZONE /etc/localtime"
chroot /mnt /bin/bash -c 'echo "en_US.UTF-8 UTF-8" >/etc/locale.gen'
chroot /mnt /bin/bash -c 'hwclock -uw && locale-gen && eselect locale set 4' || exit 1
chroot /mnt /bin/bash -c "sed -i 's/keymap=\"[^\"]*\"*/keymap=\"$_KEYMAP\"/g' /etc/conf.d/keymaps"

echo 'sys-kernel/linux-firmware @BINARY-REDISTRIBUTABLE' >>/mnt/etc/portage/package.license
echo 'sys-kernel/installkernel dracut grub' >>/mnt/etc/portage/package.use
chroot /mnt /bin/bash -c "emerge --ask=n sys-kernel/gentoo-kernel-bin sys-kernel/installkernel sys-kernel/linux-firmware" || exit 1
chroot /mnt /bin/bash -c 'eselect news read --quiet all'

is_bios && _GRUB_INSTALL="/dev/$(lsblk -dno pkname "$_BOOT_DEV")"
is_uefi && _GRUB_INSTALL='--efi-directory=/efi'

chroot /mnt /bin/bash -c "grub-install --removable $_GRUB_INSTALL" || exit 1
chroot /mnt /bin/bash -c 'grub-mkconfig -o /boot/grub/grub.cfg' || exit 1

{
  echo '# <fs> <mountpoint> <type> <opts> <dump> <pass>'
  is_bios && echo "$_BOOT_DEV /boot ext4 defaults,noatime,nodev,nosuid 0 2"
  is_uefi && echo "$_BOOT_DEV /efi vfat defaults,noatime,nodev,noexec,nosuid,umask=0077 0 2"
  echo "$_ROOT_DEV / ext4 defaults,noatime 0 1"
  is_swap_enabled "$@" && echo "/swap none swap sw 0 0"
} >/mnt/etc/fstab

is_swap_enabled "$@" && {
  chroot /mnt /bin/bash -c "fallocate -l $_SWAP_SIZE /swap" || exit 1
  chroot /mnt /bin/bash -c 'chmod 600 /swap'
  chroot /mnt /bin/bash -c 'mkswap /swap' || exit 1
}

echo "$_HOSTNAME" >/mnt/etc/hostname
sed -i "s/hostname=\"[^\"]*\"/hostname=\"$_HOSTNAME\"/g" /mnt/etc/conf.d/hostname
echo "root:$_PASSWORD" | chroot /mnt /usr/sbin/chpasswd
exit 0
