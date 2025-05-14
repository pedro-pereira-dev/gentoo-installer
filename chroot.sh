#!/bin/bash

hwclock --systohc
ln --force --symbolic "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
sed --in-place 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/g' /etc/locale.gen
locale-gen

bootctl --esp-path=/boot install
systemctl enable iwd

echo "KEYMAP=${KEYMAP}" >/etc/vconsole.conf
echo 'LANG=en_US.UTF-8' >/etc/locale.conf

echo "${SYSTEM_HOSTNAME}" >/etc/hostname
cat <<EOF >/etc/hosts
# IPv4 and IPv6 localhost aliases
127.0.0.1 ${SYSTEM_HOSTNAME} localhost
::1       ${SYSTEM_HOSTNAME} localhost
EOF

passwd <<EOF
${PASSWORD}
${PASSWORD}
EOF
