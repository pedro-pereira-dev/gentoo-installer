#!/bin/sh
# shellcheck disable=SC2016
set -eou pipefail

get_parameter() {
  _get_parameter_flag=$1 && shift
  while [ $# -ge 1 ]; do
    _get_parameter_param=$1 && shift
    [ "$_get_parameter_flag" = "$_get_parameter_param" ] && {
      _get_parameter_val='' && [ $# -ge 1 ] && _get_parameter_val=$1
      # prints out if not starting by -
      [ -n "$_get_parameter_val" ] && expr "x$_get_parameter_val" : 'x[^-]' >/dev/null &&
        echo "$_get_parameter_val" || true
    } && return 0
  done && return 1
}

get_uuid() { blkid -o export "$1" | grep ^UUID | cut -d= -f2; }

is_aarch64() { test "$(uname -m)" = aarch64; }
is_amd64() { test "$(uname -m)" = x86_64; }

is_bios() { ! is_uefi; }
is_uefi() { test -d /sys/firmware/efi; }

is_swap_enabled() { get_parameter --swap "$@" >/dev/null; }

_hostname=$(get_parameter --hostname "$@") && [ -n "$_hostname" ] ||
  while true; do
    printf 'Hostname: ' && read -r _hostname
    [ -n "$_hostname" ] && case $_hostname in
    *[!a-zA-Z0-9-]* | '') ;;
    *) break ;;
    esac
  done
_password=$(get_parameter --password "$@") && [ -n "$_password" ] ||
  while true; do
    printf 'Password: ' && read -r _password
    [ -z "$_password" ] && continue
    printf 'Confirm password: ' && read -r _password_confirmation
    [ "$_password" = "$_password_confirmation" ] && break
  done

_boot_dev=$(get_parameter --boot "$@") && [ -n "$_boot_dev" ] ||
  while true; do
    printf 'Boot device:' && read -r _boot_dev
    [ -e "$_boot_dev" ] && break
  done
_root_dev=$(get_parameter --root "$@") && [ -n "$_root_dev" ] ||
  while true; do
    printf 'Root device:' && read -r _root_dev
    [ -e "$_root_dev" ] && break
  done

is_swap_enabled "$@" && {
  _swap_size=$(get_parameter --swap "$@") && [ -z "$_swap_size" ] &&
    printf 'Swap size: [4G] ' && read -r _swap_size
  _swap_size=${_swap_size:-4G}
}

_keymap=$(get_parameter --keymap "$@") && [ -z "$_keymap" ] &&
  printf 'Keymap: [pt-latin9] ' && read -r _keymap
_keymap=${_keymap:-pt-latin9}
_timezone=$(get_parameter --timezone "$@") && [ -z "$_timezone" ] &&
  printf 'Timezone: [Europe/Lisbon] ' && read -r _timezone
_timezone=${_timezone:-Europe/Lisbon}

echo 'Installation details:'
is_bios && echo ' - Partition table: msdos'
is_uefi && echo ' - Partition table: gpt'
echo " - CPU architecture: $(uname -m)"
echo " - Hostname: $_hostname"
echo " - Password: $_password"
echo " - Boot device: $_boot_dev"
echo " - Root device: $_root_dev"
is_swap_enabled "$@" && echo " - Swap file size: $_swap_size"
echo " - Keymap: $_keymap"
echo " - Timezone: $_timezone"
echo ''
echo "All data from devices $_boot_dev and $_root_dev will be erased!"
printf 'Press any key to continue...' && read -r _

is_bios && ! mkfs.ext4 -F "$_boot_dev" && exit 1   # mbr / bios partition with EXT4
is_uefi && ! mkfs.fat -F 32 "$_boot_dev" && exit 1 # efi partition with FAT32
mkfs.ext4 -F "$_root_dev" || exit 1                # root partition with EXT4

mount -m "$_root_dev" /mnt || exit 1
is_bios && ! mount -m "$_boot_dev" /mnt/boot && exit 1
is_uefi && ! mount -m "$_boot_dev" /mnt/efi && exit 1

is_aarch64 && _arch=arm64
is_amd64 && _arch=amd64
_metadata="https://gentoo.osuosl.org/releases/$_arch/autobuilds/latest-stage3-$_arch-openrc.txt"
_build=$(curl -Lfs "$_metadata" | sed -n 6p | cut -d' ' -f1)
_stage_file="https://distfiles.gentoo.org/releases/$_arch/autobuilds/$_build"

echo 'Dowloading latest gentoo stage release...'
curl -Lf# -o /mnt/stage3-current.tar.xz "$_stage_file" || exit 1
tar xpf /mnt/stage3-current.tar.xz -C /mnt --numeric-owner --xattrs-include=*.* || exit 1
rm -fr /mnt/stage3-current.tar.xz /mnt/etc/portage/package.*

cp -L /etc/resolv.conf /mnt/etc
mount -t proc /proc /mnt/proc
mount -R /sys /mnt/sys
mount --make-rslave /mnt/sys
mount -R /dev /mnt/dev
mount --make-rslave /mnt/dev
mount -B /run /mnt/run
mount --make-slave /mnt/run

_threads=$(nproc)                               # number of threads
_total_ram=$(free -g | awk '/Mem:/ {print $2}') # in gb
_half_ram=$((_total_ram / 2))                   # in gb

_make_jobs=$_threads
[ "$_half_ram" -lt "$_threads" ] && _make_jobs=$_half_ram # min between threads and available 2gb ram per thread
[ "$_make_jobs" -lt 1 ] && _make_jobs=1                   # must have at least one job
_load_jobs=$((_make_jobs + 1))                            # extra one io thread
_portage_jobs=$((_load_jobs / 2))                         # allow half of jobs to portage

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
  echo "EMERGE_DEFAULT_OPTS=\"-aqv -j $_portage_jobs -l $_load_jobs\""
  echo 'FEATURES="$FEATURES binpkg-request-signature getbinpkg"'
  echo "MAKEOPTS=\"-j $_make_jobs -l $_load_jobs\""
} >>/mnt/etc/portage/env/gentoo-installer-make.conf

chroot /mnt /bin/bash -c 'emerge-webrsync' || exit 1
chroot /mnt /bin/bash -c "ln -fs /usr/share/zoneinfo/$_timezone /etc/localtime"
chroot /mnt /bin/bash -c 'echo "en_US.UTF-8 UTF-8" >/etc/locale.gen'
chroot /mnt /bin/bash -c 'hwclock -uw && locale-gen && eselect locale set 4' || exit 1
chroot /mnt /bin/bash -c "sed -i 's/keymap=\"[^\"]*\"*/keymap=\"$_keymap\"/g' /etc/conf.d/keymaps"

echo 'sys-kernel/linux-firmware @BINARY-REDISTRIBUTABLE' >>/mnt/etc/portage/package.license
echo 'sys-kernel/installkernel dracut grub' >>/mnt/etc/portage/package.use
chroot /mnt /bin/bash -c "emerge --ask=n sys-kernel/gentoo-kernel-bin sys-kernel/installkernel sys-kernel/linux-firmware" || exit 1
chroot /mnt /bin/bash -c 'eselect news read --quiet all'

is_bios && _grub_install="--removable /dev/$(lsblk -dno pkname "$_boot_dev")"
is_uefi && _grub_install=--efi-directory=/efi

chroot /mnt /bin/bash -c "grub-install $_grub_install" || exit 1
chroot /mnt /bin/bash -c 'grub-mkconfig -o /boot/grub/grub.cfg' || exit 1

{
  echo '# system'
  is_bios && echo "UUID=\"$(get_uuid "$_boot_dev")\" /boot ext4 defaults,noatime,nodev,nosuid 0 2"
  is_uefi && echo "UUID=\"$(get_uuid "$_boot_dev")\" /efi vfat defaults,noatime,nodev,noexec,nosuid,umask=0077 0 2"
  echo "UUID=\"$(get_uuid "$_root_dev")\" / ext4 defaults,noatime 0 1"
} >/mnt/etc/fstab

is_swap_enabled "$@" && {
  chroot /mnt /bin/bash -c "fallocate -l $_swap_size /swap" || exit 1
  chroot /mnt /bin/bash -c 'chmod 600 /swap'
  chroot /mnt /bin/bash -c 'mkswap /swap' || exit 1
  echo '/swap none swap sw 0 0' >>/mnt/etc/fstab
}

echo "$_hostname" >/mnt/etc/hostname
sed -i "s/hostname=\"[^\"]*\"/hostname=\"$_hostname\"/g" /mnt/etc/conf.d/hostname
echo "root:$_password" | chroot /mnt /usr/sbin/chpasswd
exit 0
