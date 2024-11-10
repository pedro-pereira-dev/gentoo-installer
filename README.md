# Gentoo Installer

Gentoo installation script for `amd64` with `openRC`. This script is intended to create a default gentoo base system with a distribution kernel and `doas` instead of `sudo`, as well as `networkmanager` for managing network interfaces.

### Disclaimer

This project can be used as reference for different solutions but is not the final and ultimate approach for every use case. Any contribution either in the form of issues discovering, pull requests or ideas are welcome.

## Install

To install gentoo using this project, boot up a live ISO system and run the following command to download this installation script and run it with `bash` from an elevated shell session.

This script was tested only with Ubuntu but will most likely work (famous last words) with any of the major Linux distributions as dependencies are quite common, such as `wget`, `tar`, etc.

```bash
bash <(wget -qO- https://raw.githubusercontent.com/pedro-pereira-dev/gentoo-installer/refs/heads/main/install.sh) \
  --hostname 'host' --username 'user'                                                                             \
  --device 'nvme0n1' --device-separator 'p'                                                                       \
  --efi-size '+1G' --swap-size '+32G' --root-size '+64G'                                                          \
  --timezone 'Europe/Lisbon' --keymap 'pt-latin9'
```