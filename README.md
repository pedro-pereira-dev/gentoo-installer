# Gentoo Installer

This script is used to obtain a [Gentoo](https://www.gentoo.org/) minimal installation on a system by following the steps documented on [Gentoo's handbook](https://wiki.gentoo.org/wiki/Handbook:Main_Page).
Gentoo is a Linux meta-distribution focused on user freedom of choice. As such, it does not provide an easy installation method like other popular distributions; this project aims to fill in that gap for my own needs.

*I use this project to setup and maintain all my Gentoo systems and it is not intended for community use.*

The project supports:

- *`aarch64`* and *`amd64`* CPU architectures
- *`UEFI`* boot mode with *`systemd`* as the init system
- *`ext4`* root filesystem

It installs Gentoo's distribution kernel and firmware.
Additional packages and customizations are implemented in the target systems with custom scripts by my own [_dotfiles_](https://github.com/pedro-pereira-dev/dotfiles) management system.

## Usage

This script requires _bash_ and must be run as root from a live environment.
Disk partitioning is expected to be performed beforehand: an EFI system partition, a swap partition and a root partition.
The boot, swap and root devices are all formatted by the installer, so any existing data on them is erased.

If no arguments are provided to the script, simple interactive questions are displayed to gather the required information for the installation.

### Basic usage

```sh
curl -Lfs -- https://raw.githubusercontent.com/pedro-pereira-dev/gentoo-installer/refs/heads/main/install.sh | bash
```

### Unattended usage

```sh
curl -Lfs -- https://raw.githubusercontent.com/pedro-pereira-dev/gentoo-installer/refs/heads/main/install.sh | bash -s -- \
  --hostname "$_HOSTNAME" \
  --password "$_PASSWORD" \
  --boot "$_BOOT_DEV" \
  --root "$_ROOT_DEV" \
  --swap "$_SWAP_DEV" \
  --keymap 'pt-latin9' \
  --timezone 'Europe/Lisbon' \
  --desktop
```

The optional `--desktop` flag selects Gentoo's desktop (systemd) profile.
