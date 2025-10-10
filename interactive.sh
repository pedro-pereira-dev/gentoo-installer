#!/bin/sh

usage() {
  echo -e "
Usage: ./$(basename "$0")
  --hostname <hostname>
  --password <password>
  --boot <device>
  --root <device>
  --timezone <timezone>
  --keymap <keymap>

Arguments:
  --hostname   System hostname (required)
  --password   Password for the root user (required)
  --boot       Boot disk device (e.g., /dev/sda1, /dev/nvme0n1p1) (required)
  --root       Root disk device (e.g., /dev/sda2, /dev/nvme0n1p2) (required)
  --timezone   System timezone (default: Europe/Lisbon)
  --keymap     System keymap (default: pt-latin9)
"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --hostname) SYSTEM_HOSTNAME=$2 ;;
  --password) SYSTEM_PASSWORD=$2 ;;
  --boot) SYSTEM_BOOT_DEVICE=$2 ;; --root) SYSTEM_ROOT_DEVICE=$2 ;;
  --timezone) SYSTEM_TIMEZONE=$2 ;; --keymap) SYSTEM_KEYMAP=$2 ;;
  -h | --help) usage && exit 0 ;;
  esac
  shift
  shift
done

if [[ -z ${SYSTEM_HOSTNAME} || -z ${SYSTEM_PASSWORD} || -z ${SYSTEM_BOOT_DEVICE} || -z ${SYSTEM_ROOT_DEVICE} || -z ${SYSTEM_TIMEZONE} || -z ${SYSTEM_KEYMAP} ]]; then
  echo -e "\nGathering installation setup..."
fi

if [[ -z ${SYSTEM_HOSTNAME} ]]; then
  while true; do
    read -r -p ' - System hostname: ' SYSTEM_HOSTNAME
    [[ ! -z ${SYSTEM_HOSTNAME} && ${SYSTEM_HOSTNAME} =~ ^[a-zA-Z0-9-]+$ ]] && break
  done
fi

if [[ -z ${SYSTEM_PASSWORD} ]]; then
  while true; do
    read -r -s -p ' - System password: ' SYSTEM_PASSWORD && echo
    [[ -z ${SYSTEM_PASSWORD} ]] && continue
    read -r -s -p ' - Confirm system password: ' PASSWORD_CONFIRMATION && echo
    [[ "${SYSTEM_PASSWORD}" == "${PASSWORD_CONFIRMATION}" ]] && break
  done
fi

if [[ -z ${SYSTEM_BOOT_DEVICE} || -z ${SYSTEM_ROOT_DEVICE} ]]; then
  DISK_OPTIONS=$(lsblk --noheadings --output NAME --raw | sed 's/^/\/dev\//')
  mapfile -t DISK_ARRAY <<<"${DISK_OPTIONS}"
fi

if [[ -z ${SYSTEM_BOOT_DEVICE} ]]; then
  while true; do
    echo -n ' - System boot device:'
    for i in "${!DISK_ARRAY[@]}"; do
      echo -n " [($((i + 1))) ${DISK_ARRAY[i]}]"
    done
    read -r -p ' ' DISK_OPTION
    if [[ "$DISK_OPTION" =~ ^[0-9]+$ ]] && ((DISK_OPTION > 0 && DISK_OPTION <= ${#DISK_ARRAY[@]})); then
      SYSTEM_BOOT_DEVICE=${DISK_ARRAY[$((DISK_OPTION - 1))]}
      break
    fi
  done
fi

if [[ -z ${SYSTEM_ROOT_DEVICE} ]]; then
  while true; do
    echo -n ' - System root device:'
    for i in "${!DISK_ARRAY[@]}"; do
      echo -n " [($((i + 1))) ${DISK_ARRAY[i]}]"
    done
    read -r -p ' ' DISK_OPTION
    if [[ "$DISK_OPTION" =~ ^[0-9]+$ ]] && ((DISK_OPTION > 0 && DISK_OPTION <= ${#DISK_ARRAY[@]})); then
      SYSTEM_ROOT_DEVICE=${DISK_ARRAY[$((DISK_OPTION - 1))]}
      break
    fi
  done
fi

if [[ -z ${SYSTEM_TIMEZONE} ]]; then
  read -r -p ' - System timezone: [Europe/Lisbon] ' SYSTEM_TIMEZONE
  SYSTEM_TIMEZONE=${SYSTEM_TIMEZONE:-'Europe/Lisbon'}
fi

if [[ -z ${SYSTEM_KEYMAP} ]]; then
  read -r -p ' - System keymap: [pt-latin9] ' SYSTEM_KEYMAP
  SYSTEM_KEYMAP=${SYSTEM_KEYMAP:-'pt-latin9'}
fi

echo "
Setup summary...
 - System hostname: ${SYSTEM_HOSTNAME}
 - System password: ***
 - System boot device: ${SYSTEM_BOOT_DEVICE}
 - System root device: ${SYSTEM_ROOT_DEVICE}
 - System timezone: ${SYSTEM_TIMEZONE}
 - System keymap: ${SYSTEM_KEYMAP}

All data from devices ${SYSTEM_BOOT_DEVICE} and ${SYSTEM_ROOT_DEVICE} will be erased!"
read -r -p 'Do you want to continue? [Y/n]: ' CONFIRMATION && echo ''
[[ ${CONFIRMATION} == 'n' || ${THIS_CONFIRMATION} == 'N' ]] && exit 0
