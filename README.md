# Gentoo Installer

This project provides an **opinionated, minimal installation script for Gentoo Linux** on the **`amd64`** architecture with **OpenRC**. The goal is to set up a functional base system with a distribution kernel, streamlining a process that can be complex.

-----

## Disclaimer

This script is a specific solution and may not be suitable for every use case. It is intended as a reference, and contributions - whether bug reports, pull requests, or new ideas - are always welcome.

-----

## Quick Installation

To use this script, boot from a live Linux ISO and run the following command from an elevated shell (as `root`). This command downloads the script and executes it directly with `bash`.

```bash
bash <(wget -qO- https://raw.githubusercontent.com/pedro-pereira-dev/gentoo-installer/refs/heads/main/install.sh)   \
    --hostname 'my-gentoo-host'                                                                                     \
    --password 'your_password'                                                                                      \
    --boot '/dev/sda1'                                                                                              \
    --root '/dev/sda2'                                                                                              \
    --timezone 'Europe/Lisbon'                                                                                      \
    --keymap 'pt-latin9'
```

### Dependencies

The only required dependency is **`wget`**.

### Disk preparations - example

Using `fdisk` as the formatting software and `/dev/sda` as the example block device to prepare:

```bash
sed --expression='s/\s*\([\+0-9a-zA-Z]*\).*/\1/' <<EOF | fdisk /dev/sda
    g  # create empty GPT partition table
    n  # create boot partition
    # choose default partition number
    # choose default sector number
    ${BOOT_SIZE}
    t  # label partition type
    1  # EFI system type

    n  # create root partition
    # choose default partition number
    # choose default sector number
    ${ROOT_SIZE}
    t  # label partition type
    # choose default partition number
    23 # Linux root (x86-64) type

    p  # print partition table
    w  # write changes to disk
EOF
```
