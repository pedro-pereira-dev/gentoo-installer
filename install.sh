#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2329
set -eou pipefail

is_aarch64() { test "$(uname -m)" = aarch64; }
is_amd64() { test "$(uname -m)" = x86_64; }

is_desktop() { test -n "$_desktop"; }
is_mounted() { test -n "$(lsblk -no MOUNTPOINTS "$1")"; }

is_device() { test -e "$1"; }
is_hostname() { case $1 in '' | *[!a-zA-Z0-9-]*) return 1 ;; esac }
is_not_empty() { test -n "$1"; }

get_uuid() { blkid -o export "$1" | grep ^UUID | cut -d= -f2; }
value_of() { case ${1:-} in -* | '') ;; *) echo "$1" ;; esac }

ask() { printf '%s: ' "$1" >&2 && read -r _answer && echo "$_answer"; }
ask_default() { { _answer=$(ask "$1 [$2]") || true; } && echo "${_answer:-$2}"; }
ask_until() { while true; do _answer=$(ask "$1") && "$2" "$_answer" && echo "$_answer" && return; done; }
ask_password() {
  while true; do
    printf 'Password: ' >&2 && read -rs _answer && echo >&2
    printf 'Confirm password: ' >&2 && read -rs _confirm && echo >&2
    is_not_empty "$_answer" && [ "$_confirm" = "$_answer" ] && echo "$_answer" && return
  done
}

_boot_dev='' _swap_dev='' _root_dev=''
_hostname='' _password=''
_keymap='' _timezone=''
_desktop=''

while [ $# -gt 0 ]; do
  _value=$(value_of "${2:-}")
  case $1 in
  --boot) _boot_dev=$_value ;;
  --swap) _swap_dev=$_value ;;
  --root) _root_dev=$_value ;;
  --hostname) _hostname=$_value ;;
  --password) _password=$_value ;;
  --keymap) _keymap=$_value ;;
  --timezone) _timezone=$_value ;;
  --desktop) _desktop=yes ;;
  esac
  shift
done

if [ -z "$_boot_dev" ]; then _boot_dev=$(ask_until 'Boot device' is_device); fi
if [ -z "$_swap_dev" ]; then _swap_dev=$(ask_until 'Swap device' is_device); fi
if [ -z "$_root_dev" ]; then _root_dev=$(ask_until 'Root device' is_device); fi
if [ -z "$_hostname" ]; then _hostname=$(ask_until Hostname is_hostname); fi
if [ -z "$_password" ]; then _password=$(ask_password); fi
if [ -z "$_keymap" ]; then _keymap=$(ask_default Keymap pt-latin9); fi
if [ -z "$_timezone" ]; then _timezone=$(ask_default Timezone Europe/Lisbon); fi

echo ''
echo 'Installation details:'
echo " - CPU architecture: $(uname -m)"
echo " - Boot device: $_boot_dev"
echo " - Swap device: $_swap_dev"
echo " - Root device: $_root_dev"
echo " - Hostname: $_hostname"
echo " - Password: $_password"
echo " - Keymap: $_keymap"
echo " - Timezone: $_timezone"
if is_desktop; then echo ' - Desktop profile: yes'; fi
echo ''
echo "All data from devices $_boot_dev $_swap_dev $_root_dev will be erased!"
printf 'Press any key to continue...' && read -r _
echo ''

if is_mounted "$_swap_dev"; then swapoff "$_swap_dev"; fi
if is_mounted "$_boot_dev"; then umount -A "$_boot_dev"; fi
if is_mounted "$_root_dev"; then umount -A "$_root_dev"; fi

mkfs.ext4 -F "$_root_dev"
mkfs.fat -F 32 "$_boot_dev"
mkswap "$_swap_dev"

mount -m "$_root_dev" /mnt
mount -m -o umask=0077 "$_boot_dev" /mnt/boot
swapon "$_swap_dev"

if is_aarch64; then _arch=arm64; fi
if is_amd64; then _arch=amd64; fi

_metadata="https://gentoo.osuosl.org/releases/$_arch/autobuilds/latest-stage3-$_arch-systemd.txt"
_build=$(curl -Lfs "$_metadata" | sed -n 6p | cut -d' ' -f1)
_stage_file="https://distfiles.gentoo.org/releases/$_arch/autobuilds/$_build"

echo 'Downloading latest gentoo stage release...'
curl -Lf# -o /mnt/stage3-current.tar.xz "$_stage_file"
tar xpf /mnt/stage3-current.tar.xz -C /mnt --numeric-owner --xattrs-include=*.*
rm -fr /mnt/stage3-current.tar.xz /mnt/etc/portage/package.*

cp -L /etc/resolv.conf /mnt/etc
mount -t proc /proc /mnt/proc
mount -R /sys /mnt/sys
mount --make-rslave /mnt/sys
mount -R /dev /mnt/dev
mount --make-rslave /mnt/dev
mount -B /run /mnt/run
mount --make-slave /mnt/run

_ram_gb=$(awk '/MemTotal/ {print int($2 / 1048576)}' /proc/meminfo)
_ram_jobs=$((_ram_gb / 2))

_make_jobs=$(nproc)
if [ "$_make_jobs" -gt "$_ram_jobs" ]; then _make_jobs=$_ram_jobs; fi
if [ "$_make_jobs" -lt 1 ]; then _make_jobs=1; fi

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
  echo '# portage default options'
  echo "EMERGE_DEFAULT_OPTS=\"-aqv --jobs $_make_jobs --load-average $_make_jobs\""
  echo 'FEATURES="$FEATURES binpkg-request-signature getbinpkg"'
  echo "MAKEOPTS=\"--jobs $_make_jobs --load-average $_make_jobs\""
  echo ''
  echo 'USE="dist-kernel systemd systemd-boot uki ukify"'
} >/mnt/etc/portage/env/gentoo-installer-make.conf

chroot /mnt /bin/bash -c 'emerge-webrsync'

if is_desktop; then
  _profile=$(chroot /mnt /bin/bash -c 'eselect profile list' | awk '$2 ~ /\/desktop\/systemd$/ {print $2; exit}')
  chroot /mnt /bin/bash -c "eselect profile set $_profile"
fi

echo 'LANG=en_US.UTF-8' >/mnt/etc/locale.conf
echo 'en_US.UTF-8 UTF-8' >/mnt/etc/locale.gen
chroot /mnt /bin/bash -c 'locale-gen'
chroot /mnt /bin/bash -c 'eselect locale set en_US.UTF-8'
echo "$_hostname" >/mnt/etc/hostname
echo "KEYMAP=$_keymap" >/mnt/etc/vconsole.conf
ln -sf "/usr/share/zoneinfo/$_timezone" /mnt/etc/localtime

echo "root=UUID=$(get_uuid "$_root_dev") rw quiet" >/mnt/etc/kernel/cmdline
echo 'sys-apps/systemd boot ukify' >/mnt/etc/portage/package.use
echo 'sys-kernel/installkernel dracut systemd-boot ukify uki' >>/mnt/etc/portage/package.use
chroot /mnt /bin/bash -c 'emerge --ask=n sys-kernel/installkernel'
chroot /mnt /bin/bash -c 'bootctl install'

echo 'sys-kernel/linux-firmware @BINARY-REDISTRIBUTABLE' >/mnt/etc/portage/package.license
chroot /mnt /bin/bash -c 'emerge --ask=n sys-kernel/gentoo-kernel-bin sys-kernel/linux-firmware'
chroot /mnt /bin/bash -c 'eselect news read --quiet all'

printf '[Match]\nKind=!*\nType=ether\n\n[Network]\nDHCP=yes\n' >/mnt/etc/systemd/network/50-dhcp.network
echo "root:$_password" | chroot /mnt /usr/sbin/chpasswd
exit 0
