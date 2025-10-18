#!/bin/sh
# shellcheck disable=SC2016

is_aarch64() { test "$(uname -m)" = 'aarch64'; }
is_amd64() { test "$(uname -m)" = 'x86_64'; }

is_bios() { ! is_uefi; }
is_uefi() { test -d '/sys/firmware/efi'; }

while [ $# -gt 0 ]; do
  case "$1" in
  --hostname) _HOSTNAME=$2 ;; --password) _PASSWORD=$2 ;;
  --boot) _BOOT_DEV=$2 ;; --swap) _SWAP_DEV=$2 ;; --root) _ROOT_DEV=$2 ;;
  --keymap) _KEYMAP=$2 ;; --timezone) _TIMEZONE=$2 ;;
  esac
  shift && shift
done

[ -z "$_HOSTNAME" ] && [ -z "$_PASSWORD" ] && [ ! -e "$_BOOT_DEV" ] && [ ! -e "$_SWAP_DEV" ] && [ ! -e "$_ROOT_DEV" ] && _INTERACTIVE='true'

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
[ -z "$_SWAP_DEV" ] && while true; do
  printf 'Swap device:' && read -r _SWAP_DEV
  [ -e "$_SWAP_DEV" ] && break
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
echo " - System swap device: $_SWAP_DEV"
echo " - System root device: $_ROOT_DEV"
echo " - System keymap: $_KEYMAP"
echo " - System timezone: $_TIMEZONE"
echo ''
echo "All data from devices $_BOOT_DEV, $_SWAP_DEV and $_ROOT_DEV will be erased!"

if [ -n "$_INTERACTIVE" ]; then
  printf 'Do you want to continue? [Y/n]: ' && read -r _CONFIRMATION
  [ ! "$_CONFIRMATION" = 'n' ] && [ ! "$_CONFIRMATION" = 'N' ] || exit 0
else
  echo 'Starting installation in a few seconds...'
  sleep 10
fi

is_bios && _BOOT_FS='mkfs.ext4'
is_bios && _BOOT_MOUNT='/mnt/boot'
is_bios && _BOOT_PLATFORM='pc'

is_uefi && _BOOT_FS='mkfs.fat -F 32'
is_uefi && _BOOT_MOUNT='/mnt/efi'
is_uefi && _BOOT_PLATFORM='efi-64'

yes | $_BOOT_FS "$_BOOT_DEV" # boot partition with FAT32 for UEFI and EXT4 for BIOS
yes | mkswap "$_SWAP_DEV"    # swap partition
yes | mkfs.ext4 "$_ROOT_DEV" # root partition with EXT4

mount -m "$_ROOT_DEV" /mnt
swapon "$_SWAP_DEV"
mount -m "$_BOOT_DEV" "$_BOOT_MOUNT"

is_aarch64 && _ARCH='arm64'
is_amd64 && _ARCH='amd64'

_METADATA="https://gentoo.osuosl.org/releases/$_ARCH/autobuilds/latest-stage3-$_ARCH-openrc.txt"
_BUILD=$(curl -Lfs "$_METADATA" | sed -n '6p' | cut -d' ' -f1)
_STAGE_FILE="https://distfiles.gentoo.org/releases/$_ARCH/autobuilds/$_BUILD"

curl -Lf "$_STAGE_FILE" >/mnt/stage3-current.tar.xz
tar xpf /mnt/stage3-current.tar.xz -C /mnt --numeric-owner --xattrs-include='*.*'
rm -fr /mnt/etc/portage/package.*

_THREAD_RAM=$(($(free -g | awk '/Mem:/ {print $2}') / 2))       # RAM in GB divided by 2GB
_THREADS=$(nproc)                                               # number of threads
_MAKE_JOBS=$((_THREAD_RAM < _THREADS ? _THREAD_RAM : _THREADS)) # min(RAM / 2GB, number of threads)
_MAKE_JOBS=$((_MAKE_JOBS > 1 ? _MAKE_JOBS : 1))                 # max(make_opt_jobs, 1)
_LOAD_JOBS=$((_MAKE_JOBS + 1))                                  # max number of jobs plus one for io
_PORTAGE_JOBS=$(((_MAKE_JOBS + 1) / 2))                         # ceiling of half max number of jobs

mkdir -p /mnt/etc/portage/env
echo '*/* gentoo-installer-make.conf' >>/mnt/etc/portage/package.env
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
  echo "GRUB_PLATFORMS=\"$_BOOT_PLATFORM\""
  echo ''
  echo '# portage default options'
  echo "EMERGE_DEFAULT_OPTS=\"--ask --jobs $_PORTAGE_JOBS --load-average $_LOAD_JOBS --quiet --verbose\""
  echo "FEATURES=\"$FEATURES binpkg-request-signature getbinpkg\""
  echo "MAKEOPTS=\"--jobs $_MAKE_JOBS --load-average $_LOAD_JOBS\""
} >>/mnt/etc/portage/env/gentoo-installer-make.conf

cp -L /etc/resolv.conf /mnt/etc/
mount --types proc /proc /mnt/proc
mount --rbind /sys /mnt/sys
mount --make-rslave /mnt/sys
mount --rbind /dev /mnt/dev
mount --make-rslave /mnt/dev
mount --bind /run /mnt/run
mount --make-slave /mnt/run

chroot /mnt /bin/bash -c 'emerge-webrsync'
chroot /mnt /bin/bash -c "ln -fs '/usr/share/zoneinfo/$_TIMEZONE' /etc/localtime"
chroot /mnt /bin/bash -c "sed -i 's/keymap=\"us\"/keymap=\"$_KEYMAP\"/g' /etc/conf.d/keymaps"
chroot /mnt /bin/bash -c 'echo "en_US.UTF-8 UTF-8" >/etc/locale.gen'
chroot /mnt /bin/bash -c 'locale-gen && eselect locale set 4'
chroot /mnt /bin/bash -c 'env-update'

mkdir -p /mnt/etc/portage/package.license /mnt/etc/portage/package.use
{
  echo '#!/bin/sh'
  echo 'sys-kernel/linux-firmware @BINARY-REDISTRIBUTABLE'
} >>/mnt/etc/portage/package.license/gentoo-installer-license.conf
{
  echo '#!/bin/sh'
  echo 'sys-kernel/installkernel dracut grub'
} >>/mnt/etc/portage/package.use/gentoo-installer-use.conf
chroot /mnt /bin/bash -c 'emerge --ask=n sys-kernel/gentoo-kernel-bin sys-kernel/installkernel sys-kernel/linux-firmware'
chroot /mnt /bin/bash -c 'eselect news read --quiet all'

_GRUB_CONFIG='/boot/grub/grub.cfg'

is_bios && _BOOT_FSTAB="$_BOOT_DEV /boot ext4 defaults,noatime,nodev,nosuid 0 2"
# is_bios && _GRUB_CONFIG='/boot/grub/grub.cfg'
is_bios && _GRUB_INSTALL="$_BOOT_DEV"
is_bios && _GRUB_INSTALL="${_GRUB_INSTALL%?}" # removes last character

is_uefi && _BOOT_FSTAB="$_BOOT_DEV /efi vfat defaults,noatime,nodev,nosuid,umask=0077 0 2"
# is_uefi && is_aarch64 && _GRUB_CONFIG='/efi/EFI/gentoo/grubaa64.cfg'
# is_uefi && is_amd64 && _GRUB_CONFIG='/efi/EFI/gentoo/grub.cfg'
is_uefi && _GRUB_INSTALL='--efi-directory=/efi'

chroot /mnt /bin/bash -c "grub-install $_GRUB_INSTALL"
chroot /mnt /bin/bash -c "grub-mkconfig -o $_GRUB_CONFIG"

{
  echo '# <fs> <mountpoint> <type> <opts> <dump> <pass>'
  echo "$_BOOT_FSTAB"
  echo "$_SWAP_DEV none swap sw 0 0"
  echo "$_ROOT_DEV / ext4 defaults,noatime 0 1"
} >/mnt/etc/fstab
echo "$_HOSTNAME" >/mnt/etc/hostname
echo "root:$_PASSWORD" | chroot /mnt /usr/sbin/chpasswd
rm -f /mnt/stage3-current.tar.xz
