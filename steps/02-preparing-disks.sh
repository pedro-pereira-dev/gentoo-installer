#!/bin/bash

clear
echo -e '
  ______ ______                                        _                    _ _      _          
 / __   (_____ \                                      (_)                  | (_)    | |         
| | //| | ____) )__ ____   ____ ____ ____   ____  ____ _ ____   ____ ___ _ | |_  ___| |  _  ___ 
| |// | |/_____(___)  _ \ / ___) _  )  _ \ / _  |/ ___) |  _ \ / _  (___) || | |/___) | / )/___)
|  /__| |_______   | | | | |  ( (/ /| | | ( ( | | |   | | | | ( ( | |  ( (_| | |___ | |< (|___ |
 \_____/(_______)  | ||_/|_|   \____) ||_/ \_||_|_|   |_|_| |_|\_|| |   \____|_(___/|_| \_|___/ 
                   |_|              |_|                       (_____|                           
________________________________________________________________________________________________
'

# partitions disk
# a blank line will send a return to fdisk
sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' <<EOF | fdisk ${THIS_DEVICE}
    g  # create empty GPT partition table
    n  # create EFI partition
    # choose default partition number
    # choose default sector number
    ${THIS_EFI_SIZE}
    y  # remove signature if it exists
    t  # create EFI partition type
    1  # EFI system type
    n  # create SWAP partition
    # choose default partition number
    # choose default sector number
    ${THIS_SWAP_SIZE}
    y  # remove signature if it exists
    t  # create SWAP partition type
    # choose default partition number
    19 # Linux swap type
    n  # create ROOT partition
    # choose default partition number
    # choose default sector number
    ${THIS_ROOT_SIZE}
    y  # remove signature if it exists
    t  # create ROOT partition type
    # choose default partition number
    23 # Linux root (x86-64) type
    w  # write changes to disk
EOF

# fat32 BOOT
mkfs.vfat -F 32 ${THIS_DEVICE}${THIS_DEVICE_SEPARATOR}1
# linux-swap SWAP
mkswap ${THIS_DEVICE}${THIS_DEVICE_SEPARATOR}2
swapon ${THIS_DEVICE}${THIS_DEVICE_SEPARATOR}2
# ext4 ROOT
mkfs.ext4 ${THIS_DEVICE}${THIS_DEVICE_SEPARATOR}3 <<EOF
y
EOF
