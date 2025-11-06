#!/bin/sh
# shellcheck disable=2015
set -eou pipefail

create_custom_iso() {
  [ $# -ne 1 ] && return 1

  _ARCH=$1
  [ "$_ARCH" = amd64 ] && _ALPINE_ARCH=x86_64
  [ "$_ARCH" = arm64 ] && _ALPINE_ARCH=aarch64

  [ ! -f /tmp/alpine-overlay.apkvol ] && {
    curl -Lf# -o /tmp/alpine-overlay.apkvol \
      https://github.com/macmpi/alpine-linux-headless-bootstrap/raw/refs/heads/main/headless.apkovl.tar.gz ||
      return 1
  }

  [ ! -f "/tmp/alpine-version-$_ARCH.txt" ] && {
    curl -Lfs "https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/$_ALPINE_ARCH/latest-releases.yaml" |
      grep -m 1 version | awk '{ print $NF }' >"/tmp/alpine-version-$_ARCH.txt" ||
      return 1
  }

  [ ! -f "/tmp/alpine-$_ARCH.iso" ] && {
    echo "Downloading alpine ($_ARCH) iso:"
    curl -Lf# -o "/tmp/alpine-$_ARCH.iso" \
      "https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/$_ALPINE_ARCH/alpine-standard-$(
        cat "/tmp/alpine-version-$_ARCH.txt"
      )-$_ALPINE_ARCH.iso" ||
      return 1
  }

  [ ! -f "/tmp/custom-alpine-$_ARCH.iso" ] && {
    podman run \
      --pull always \
      --rm \
      -v "/tmp/alpine-$_ARCH.iso":"/tmp/alpine-$_ARCH.iso":ro \
      -v /tmp/alpine-overlay.apkvol:/tmp/alpine-overlay.apkvol:ro \
      -v /tmp:/workspace \
      docker.io/alpine:latest \
      sh -c "\
        apk add --no-cache xorriso && \
        xorriso \
        -indev /tmp/alpine-$_ARCH.iso \
        -outdev /workspace/custom-alpine-$_ARCH.iso \
        -map /tmp/alpine-overlay.apkvol /headless.apkovl.tar.gz \
        -boot_image any replay" ||
      return 1
  }

  return 0
}

create_container() {
  [ $# -ne 2 ] && return 1

  _ARCH=$1 && _BOOT_MODE=$2
  create_custom_iso "$_ARCH" || return 1

  [ "$_ARCH" = amd64 ] && _ISO=/tmp/custom-alpine-amd64.iso && _CONTAINER_IMAGE=docker.io/qemux/qemu:latest
  [ "$_ARCH" = arm64 ] && _ISO=/tmp/custom-alpine-arm64.iso && _CONTAINER_IMAGE=docker.io/qemux/qemu-arm:latest

  podman run \
    --device=/dev/kvm \
    --name gentoo-installer-test \
    --pull always \
    --replace \
    -d \
    -e BOOT_MODE="$_BOOT_MODE" \
    -e CPU_CORES=$(($(nproc) - 1)) \
    -e DISK_SIZE=16G \
    -e RAM_SIZE=$((($(free -g | awk '/Mem:/ {print $4}') + 1) / 2)) \
    -p 2222:22 -p 8006:8006 \
    -v "$_ISO":/boot.iso \
    "$_CONTAINER_IMAGE" ||
    return 1

  return 0
}

run_on_target() {
  ssh-keygen -R '[localhost]:2222' >/dev/null 2>&1 || return 1
  ssh -o ConnectTimeout=1 -o StrictHostKeyChecking=accept-new -p 2222 -q root@localhost "$@"
}

test_connection() {
  printf 'Attempting to connect to target...' && start_time=$(date +%s) && while true; do
    current_time=$(date +%s) && elapsed=$((current_time - start_time))
    [ "$elapsed" -ge 300 ] && echo '' && return 1
    run_on_target 'exit' && echo '' && return 0
    printf '.' && sleep 1
  done
}

cleanup_containers() { podman rm -f gentoo-installer-test static-server; }

prepare_container() {
  [ $# -ne 2 ] && return 1

  _ARCH=$1 && _BOOT_MODE=$2
  cleanup_containers && create_container "$_ARCH" "$_BOOT_MODE" ||
    { cleanup_containers && return 1; }

  test_connection &&
    run_on_target 'setup-apkrepos -1 && apk update' &&
    run_on_target 'apk add curl dosfstools e2fsprogs tar util-linux xz' ||
    { cleanup_containers && return 1; }

  run_on_target 'wipefs -a /dev/sda*' && {
    [ "$_BOOT_MODE" = legacy ] && run_on_target 'printf "o\nn\n \n \n \n+512M\na\nn\n \n \n \n \np\nw\n" | fdisk /dev/sda' ||
      { [ "$_BOOT_MODE" = uefi ] && run_on_target 'printf "g\nn\n \n \n+512M\nY\nt\n1\nn\n \n \n \nY\np\nw\n" | fdisk /dev/sda'; }
  } || { cleanup_containers && return 1; }

  return 0
}

run_test() {
  [ $# -ne 2 ] && return 1

  _ARCH=$1 && _BOOT_MODE=$2
  prepare_container "$_ARCH" "$_BOOT_MODE" ||
    { cleanup_containers && return 1; }

  podman run \
    --name static-server \
    --pull always \
    --replace \
    -d \
    -p 8080:80 \
    -v "$(pwd)":/usr/local/apache2/htdocs/ \
    docker.io/httpd:latest &&
    run_on_target 'curl -Lfs -o install.sh http://host.containers.internal:8080/install.sh' &&
    podman rm -f static-server ||
    { cleanup_containers && return 1; }

  run_on_target "yes | sh install.sh \
    --hostname gentoo-installer-test-$_ARCH-$_BOOT_MODE \
    --password root \
    --boot /dev/sda1 \
    --root /dev/sda2 \
    --swap 4G" ||
    { cleanup_containers && return 1; }

  test_connection &&
    run_on_target 'echo "PermitEmptyPasswords yes" >> /mnt/etc/ssh/sshd_config.d/gentoo-installer-test.conf' &&
    run_on_target 'echo "PermitRootLogin yes" >> /mnt/etc/ssh/sshd_config.d/gentoo-installer-test.conf' &&
    run_on_target 'chroot /mnt /bin/bash -c "passwd -d root && rc-update add sshd default" && reboot' ||
    { cleanup_containers && return 1; }

  sleep 60

  test_connection &&
    run_on_target 'emerge --ask=n app-misc/fastfetch && fastfetch && poweroff' ||
    { cleanup_containers && return 1; }

  cleanup_containers && return 0
}

create_and_run_test() {
  [ $# -ne 2 ] && return 1

  _ARCH=$1 && _BOOT_MODE=$2
  printf 'Running test for: %s-%s' "$_ARCH" "$_BOOT_MODE"
  run_test "$_ARCH" "$_BOOT_MODE" >.tests/"$_ARCH"-"$_BOOT_MODE".log 2>&1 &&
    echo ' OK' || echo ' ERROR'
}

rm -fr .tests && mkdir -p .tests

create_and_run_test amd64 uefi
create_and_run_test amd64 legacy
create_and_run_test arm64 uefi
create_and_run_test arm64 legacy

exit 0
