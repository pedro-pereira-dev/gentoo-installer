#!/bin/bash

clear
echo -e '
  ______  __                      ___ _                   _                                                
 / __   |/  |                    / __|_)                 (_)                               _               
| | //| /_/ |___ ____ ___  ____ | |__ _  ____ _   _  ____ _ ____   ____ ___ ___ _   _  ___| |_  ____ ____  
| |// | | | (___) ___) _ \|  _ \|  __) |/ _  | | | |/ ___) |  _ \ / _  (___)___) | | |/___)  _)/ _  )    \ 
|  /__| | | |  ( (__| |_| | | | | |  | ( ( | | |_| | |   | | | | ( ( | |  |___ | |_| |___ | |_( (/ /| | | |
 \_____/  |_|   \____)___/|_| |_|_|  |_|\_|| |\____|_|   |_|_| |_|\_|| |  (___/ \__  (___/ \___)____)_|_|_|
                                       (_____|                   (_____|       (____/                      
___________________________________________________________________________________________________________
'

# reads from template file
[[ ! -z $1 ]] && source $1 && scripted_host=$(basename $1 | sed 's/\.props//')

# reads username
[[ -z ${scripted_user} ]] && read -p ' - User: ' THIS_USER
[[ ! -z ${scripted_user} ]] && THIS_USER=${scripted_user}

# reads password
read -s -p ' - Password: ' THIS_PASSWORD && echo ''
read -s -p ' - Confirm password: ' THIS_PASSWORD_CONFIRMATION && echo ''

# reads hostname
[[ -z ${scripted_host} ]] && read -p ' - Host: ' THIS_HOST
[[ ! -z ${scripted_host} ]] && THIS_HOST=${scripted_host}

# reads device name
[[ -z ${scripted_device} ]] && read -p ' - Device name /dev/_ (default is nvme0n1): ' THIS_DEVICE
[[ ! -z ${scripted_device} ]] && THIS_DEVICE=${scripted_device}

# reads device separator
[[ -z ${scripted_separator} ]] && read -p ' - Device separator /dev/nvme0n1_1 (default is p, type "?" for an empty separator symbol): ' THIS_DEVICE_SEPARATOR
[[ ! -z ${scripted_separator} ]] && THIS_DEVICE_SEPARATOR=${scripted_separator}

# reads partition sizes
[[ -z ${scripted_efi} ]] && read -p ' - EFI partition size (default is +1G, type "?" for remaining disk size): ' THIS_EFI_SIZE
[[ ! -z ${scripted_efi} ]] && THIS_EFI_SIZE=${scripted_efi}
[[ -z ${scripted_swap} ]] && read -p ' - SWAP partition size (default is +8G, type "?" for remaining disk size): ' THIS_SWAP_SIZE
[[ ! -z ${scripted_swap} ]] && THIS_SWAP_SIZE=${scripted_swap}
[[ -z ${scripted_root} ]] && read -p ' - ROOT partition size (default is "?" for remaining disk size, type "+128G" to change it to something else): ' THIS_ROOT_SIZE
[[ ! -z ${scripted_root} ]] && THIS_ROOT_SIZE=${scripted_root}

# reads timezone
[[ -z ${scripted_timezone} ]] && read -p ' - Timezone (default is Europe/Lisbon): ' THIS_TIMEZONE
[[ ! -z ${scripted_timezone} ]] && THIS_TIMEZONE=${scripted_timezone}

# reads keymap
[[ -z ${scripted_keymap} ]] && read -p ' - Keymap (default is pt-latin9): ' THIS_KEYMAP
[[ ! -z ${scripted_keymap} ]] && THIS_KEYMAP=${scripted_keymap}

# gets current stage3 metadata
METADATA=$(wget -qO- https://distfiles.gentoo.org/releases/amd64/autobuilds/latest-stage3-amd64-openrc.txt)
# gets current stage3 file name
METADATA=$(echo ${METADATA} | grep -oE '[0-9]*T[0-9]*Z/stage3-amd64-openrc-[0-9]*T[0-9]*Z.tar.xz')
# gets current stage3 file URL
THIS_STAGE_FILE="https://distfiles.gentoo.org/releases/amd64/autobuilds/${METADATA}"

# sets default values
THIS_DEVICE=/dev/${THIS_DEVICE:-nvme0n1}
THIS_DEVICE_SEPARATOR=${THIS_DEVICE_SEPARATOR:-p}
THIS_EFI_SIZE=${THIS_EFI_SIZE:-+1G}
THIS_SWAP_SIZE=${THIS_SWAP_SIZE:-+8G}
THIS_ROOT_SIZE=${THIS_ROOT_SIZE:-?}
THIS_TIMEZONE=${THIS_TIMEZONE:-Europe/Lisbon}
THIS_KEYMAP=${THIS_KEYMAP:-pt-latin9}

# checks if password and password confirmation match
[[ ${THIS_PASSWORD} != ${THIS_PASSWORD_CONFIRMATION} ]] && echo -e 'Passwords do not match!\n' && exit 1

# sets special input variables values
[[ ${THIS_DEVICE_SEPARATOR} = $'?' ]] && THIS_DEVICE_SEPARATOR=''
[[ ${THIS_EFI_SIZE} = $'?' ]] && THIS_EFI_SIZE=' '
[[ ${THIS_SWAP_SIZE} = $'?' ]] && THIS_SWAP_SIZE=' '
[[ ${THIS_ROOT_SIZE} = $'?' ]] && THIS_ROOT_SIZE=' '

# prints out user choices
echo -e "
Confirm your choices:

User: ${THIS_USER}
Password: ********
Host: ${THIS_HOST}
Device: ${THIS_DEVICE}
Device separator: ${THIS_DEVICE_SEPARATOR}
EFI partition size: ${THIS_EFI_SIZE}
SWAP partition size: ${THIS_SWAP_SIZE}
ROOT partition size: ${THIS_ROOT_SIZE}
Stage file: ${THIS_STAGE_FILE}
Timezone: ${THIS_TIMEZONE}
Keymap: ${THIS_KEYMAP}
"

# confirms user choices
read -p 'Are you sure you want to continue [Y/n]? ' CONFIRMATION_DIALOG && echo ''
[[ ${CONFIRMATION_DIALOG} == 'n' || ${CONFIRMATION_DIALOG} == 'N' ]] && exit 1

# checks if any empty variable
[[ -z ${THIS_USER} ]] && echo 'User is empty' && exit 1
[[ -z ${THIS_HOST} ]] && echo 'Host is empty' && exit 1
[[ -z ${THIS_STAGE_FILE} ]] && echo 'Stage file is empty' && exit 1
[[ -z ${THIS_TIMEZONE} ]] && echo 'Timezone is empty' && exit 1
[[ -z ${THIS_KEYMAP} ]] && echo 'Keymap is empty' && exit 1
