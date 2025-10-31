#!/bin/sh
# shellcheck disable=SC2016

is_aarch64() { test "$(uname -m)" = 'aarch64'; }
is_amd64() { test "$(uname -m)" = 'x86_64'; }

is_bios() { ! is_uefi; }
is_uefi() { test -d '/sys/firmware/efi'; }

while [ $# -gt 0 ]; do
  case "$1" in
  --hostname) _HOSTNAME=$2 ;; --password) _PASSWORD=$2 ;;
  --boot) _BOOT_DEV=$2 ;; --root) _ROOT_DEV=$2 ;;
  --keymap) _KEYMAP=$2 ;; --timezone) _TIMEZONE=$2 ;;
  esac
  shift && shift
done

[ -z "$_HOSTNAME" ] && while true; do
  printf 'Hostname: ' && read -r _HOSTNAME
  [ -n "$_HOSTNAME" ] && case "$_HOSTNAME" in
  *[!a-zA-Z0-9-]* | '') ;;
  *) break ;;
  esac
done
[ -z "$_PASSWORD" ] && while true; do
  printf 'Password: ' && read -r _PASSWORD
  [ -z "$_PASSWORD" ] && continue
  printf 'Confirm password: ' && read -r _PASSWORD_CONFIRMATION
  [ "$_PASSWORD" = "$_PASSWORD_CONFIRMATION" ] && break
done

[ -z "$_BOOT_DEV" ] && while true; do
  printf 'Boot device:' && read -r _BOOT_DEV
  [ -e "$_BOOT_DEV" ] && break
done
[ -z "$_ROOT_DEV" ] && while true; do
  printf 'Root device:' && read -r _ROOT_DEV
  [ -e "$_ROOT_DEV" ] && break
done

[ -z "$_KEYMAP" ] &&
  printf 'Keymap: [pt-latin9] ' && read -r _KEYMAP
_KEYMAP=${_KEYMAP:-'pt-latin9'}
[ -z "$_TIMEZONE" ] &&
  printf 'Timezone: [Europe/Lisbon] ' && read -r _TIMEZONE
_TIMEZONE=${_TIMEZONE:-'Europe/Lisbon'}

echo 'Installation details:'
is_bios && echo ' - System partition table: msdos'
is_uefi && echo ' - System partition table: gpt'
echo " - System architecture: $(uname -m)"
echo " - System hostname: $_HOSTNAME"
echo " - System password: $_PASSWORD"
echo " - System boot device: $_BOOT_DEV"
echo " - System root device: $_ROOT_DEV"
echo " - System keymap: $_KEYMAP"
echo " - System timezone: $_TIMEZONE"
echo ''
echo "All data from devices $_BOOT_DEV and $_ROOT_DEV will be erased!"
printf 'Press any key to continue...' && read -r _

is_bios && yes | mkfs.ext4 "$_BOOT_DEV"      # mbr / bios partition with EXT4
is_uefi && yes | mkfs.fat -F 32 "$_BOOT_DEV" # efi partition with FAT32
yes | mkfs.ext4 "$_ROOT_DEV"                 # root partition with EXT4

is_bios && _BOOT_MOUNT='/boot'
is_uefi && _BOOT_MOUNT='/efi'

mount -m "$_ROOT_DEV" /mnt
mount -m "$_BOOT_DEV" "/mnt$_BOOT_MOUNT"

is_aarch64 && _ARCH='arm64'
is_amd64 && _ARCH='amd64'
_METADATA="https://gentoo.osuosl.org/releases/$_ARCH/autobuilds/latest-stage3-$_ARCH-openrc.txt"
_BUILD=$(curl -Lfs "$_METADATA" | sed -n '6p' | cut -d' ' -f1)
_STAGE_FILE="https://distfiles.gentoo.org/releases/$_ARCH/autobuilds/$_BUILD"

echo 'Dowloading latest gentoo stage release...'
curl -Lf --progress-bar -o /mnt/stage3-current.tar.xz "$_STAGE_FILE"
tar xpf /mnt/stage3-current.tar.xz -C /mnt --numeric-owner --xattrs-include='*.*'
rm -fr /mnt/etc/portage/package.*

cp -L /etc/resolv.conf /mnt/etc/
mount --types proc /proc /mnt/proc
mount --rbind /sys /mnt/sys
mount --make-rslave /mnt/sys
mount --rbind /dev /mnt/dev
mount --make-rslave /mnt/dev
mount --bind /run /mnt/run
mount --make-slave /mnt/run

_THREAD_RAM=$(($(free -g | awk '/Mem:/ {print $2}') / 2))       # RAM in GB divided by 2GB
_THREADS=$(nproc)                                               # number of threads
_MAKE_JOBS=$((_THREAD_RAM < _THREADS ? _THREAD_RAM : _THREADS)) # min(RAM / 2GB, number of threads)
_MAKE_JOBS=$((_MAKE_JOBS > 1 ? _MAKE_JOBS : 1))                 # max(make_opt_jobs, 1)
_LOAD_JOBS=$((_MAKE_JOBS + 1))                                  # max number of jobs plus one for io
_PORTAGE_JOBS=$(((_MAKE_JOBS + 1) / 2))                         # ceiling of half max number of jobs

is_bios && _PLATFORM='pc'
is_uefi && _PLATFORM='efi-64'
mkdir -p /mnt/etc/portage/env /mnt/etc/portage/package.env
echo '*/* 0-gentoo-installer-make.conf' >>/mnt/etc/portage/package.env/0-gentoo-installer-env.conf
{
  echo '# values modified by the installation script'
  echo 'COMMON_FLAGS="-march=native -O2 -pipe"'
  echo 'RUSTFLAGS="$RUSTFLAGS -C target-cpu=native"'
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
  echo "GRUB_PLATFORMS=\"$_PLATFORM\""
  echo ''
  echo '# portage default options'
  echo "EMERGE_DEFAULT_OPTS=\"--ask --jobs $_PORTAGE_JOBS --load-average $_LOAD_JOBS --quiet --verbose\""
  echo "FEATURES=\"$FEATURES binpkg-request-signature getbinpkg\""
  echo "MAKEOPTS=\"--jobs $_MAKE_JOBS --load-average $_LOAD_JOBS\""
} >>/mnt/etc/portage/env/0-gentoo-installer-make.conf

chroot /mnt /bin/bash -c 'emerge-webrsync'
chroot /mnt /bin/bash -c "ln -fs '/usr/share/zoneinfo/$_TIMEZONE' /etc/localtime"
chroot /mnt /bin/bash -c 'hwclock -uw'
chroot /mnt /bin/bash -c 'echo "en_US.UTF-8 UTF-8" >/etc/locale.gen'
chroot /mnt /bin/bash -c 'locale-gen && eselect locale set 4'
chroot /mnt /bin/bash -c "sed -i 's/keymap=\"[^\"]*\"*/keymap=\"$_KEYMAP\"/g' /etc/conf.d/keymaps"
chroot /mnt /bin/bash -c 'env-update'

mkdir -p /mnt/etc/portage/package.declare /mnt/etc/portage/package.license /mnt/etc/portage/package.use
{
  echo '#!/bin/sh'
  echo 'sys-kernel/gentoo-kernel-bin'
  echo 'sys-kernel/installkernel'
  echo 'sys-kernel/linux-firmware'
} >>/mnt/etc/portage/package.declare/0-gentoo-installer-declare.conf
{
  echo '#!/bin/sh'
  echo 'sys-kernel/linux-firmware @BINARY-REDISTRIBUTABLE'
} >>/mnt/etc/portage/package.license/0-gentoo-installer-license.conf
{
  echo '#!/bin/sh'
  echo 'sys-kernel/installkernel dracut grub'
} >>/mnt/etc/portage/package.use/0-gentoo-installer-use.conf
chroot /mnt /bin/bash -c 'emerge --ask=n \
  sys-kernel/gentoo-kernel-bin \
  sys-kernel/installkernel \
  sys-kernel/linux-firmware \
'
chroot /mnt /bin/bash -c 'eselect news read --quiet all'

is_bios && _GRUB_INSTALL="/dev/$(lsblk -dno pkname "$_BOOT_DEV")"
is_uefi && _GRUB_INSTALL='--efi-directory=/efi --removable'

chroot /mnt /bin/bash -c "grub-install $_GRUB_INSTALL"
chroot /mnt /bin/bash -c 'grub-mkconfig -o /boot/grub/grub.cfg'

{
  echo '# <fs> <mountpoint> <type> <opts> <dump> <pass>'
  is_bios && echo "$_BOOT_DEV $_BOOT_MOUNT ext4 defaults,noatime,nodev,nosuid 0 2"
  is_uefi && echo "$_BOOT_DEV $_BOOT_MOUNT vfat defaults,noatime,nodev,noexec,nosuid,umask=0077 0 2"
  echo "$_ROOT_DEV / ext4 defaults,noatime 0 1"
} >/mnt/etc/fstab

echo "$_HOSTNAME" >/mnt/etc/hostname
sed -i "s/hostname=\"[^\"]*\"/hostname=\"$_HOSTNAME\"/g" /mnt/etc/conf.d/hostname
echo "root:$_PASSWORD" | chroot /mnt /usr/sbin/chpasswd

rm -f /mnt/stage3-current.tar.xz
