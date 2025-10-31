# Gentoo Installer

This script is used to obtain a [Gentoo](https://www.gentoo.org/) minimal installation on a systemm.
Gentoo is a linux meta-distribution focused on user freedom of choice. As such it does not provide an easy installation method like other popular distributions, this project aims to fill in that gap for my own needs.

*I use this project to setup and maintain all my Gentoo systems and is not intended for community use.*

The project supports both *`aarch64`* and *`amd64`* CPU architectures, and both *`BIOS / MBR legacy`* and *`UEFI`* boot mode.
It installs common utilities and Gentoo's distribution kernel.
Additional packages and customizations are implemented in the target systems with custom scripts by my own [_dotfiles_](https://github.com/pedro-pereira-dev/dotfiles) management system.

## Usage

This script is _POSIX_ compliant so it can be executed with any compatible shell and expects that disk partioning is performed beforehand by accepting a target boot and root filesystem device partition.
If no arguments are provided to the script, simple interactive questions are displayed to gather the required information for the installation.

### Basic usage

```sh
_TMP_FILE=$(mktemp)
curl -Lfs -o "$_TMP_FILE" 'https://raw.githubusercontent.com/pedro-pereira-dev/gentoo-installer/refs/heads/main/install.sh'
sh "$_TMP_FILE"
```

### Unattended usage

```sh
_TMP_FILE=$(mktemp)
curl -Lfs -o "$_TMP_FILE" 'https://raw.githubusercontent.com/pedro-pereira-dev/gentoo-installer/refs/heads/main/install.sh'
sh "$_TMP_FILE" \
  --hostname "$_HOSTNAME" \
  --password "$_PASSWORD" \
  --boot "$_BOOT_DEV" \
  --root "$_ROOT_DEV" \
  --keymap 'pt-latin9' \
  --timezone 'Europe/Lisbon'
```
