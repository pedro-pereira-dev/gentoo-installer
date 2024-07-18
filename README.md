# Gentoo Installer

Gentoo installation script for `amd64` with `openRC`. This script is intended to create a default gentoo base system (even though opinionated for my use cases) with a distribution kernel and `doas` instead of `sudo`, as well as `networkmanager` for managing network interfaces.

### Disclaimer

This project can be used as reference for different solutions but is not the final and ultimate approach as some installation approaches are very opinionated, such as the ones referred above. Any contribution either in the form of issues discovering, pull requests or ideas are welcome.

## Install

This installation process has two install approaches, a _install_ script that assumes that the required dependency `wget` is installed and assumes that the project was cloned to the local filesystem, and a more comfy approach _web-install_ that goes through the whole installation with minimal interaction by automatically cloning the project and executing it, `git` is an additional dependency in the latter approach.

This script assumes that it is being executed from a root shell:

```bash
sudo su # for sudo
doas su # for doas
...
```

### _install_

To install gentoo in a system by going through all the setup steps interactively:

```bash
# curl, git and wget is needed
git clone https://github.com/pedro-pereira-dev/gentoo-installer
gentoo-installer/install.sh 2>&1 | tee ./install.log
```

To install gentoo in a system from a templated system configuration, a `hostname` should be passed as argument:

```bash
# curl, git and wget is needed
git clone https://github.com/pedro-pereira-dev/gentoo-installer
gentoo-installer/install.sh gentoo-laptop-msi-es 2>&1 | tee ./install.log
```

### _web-install_ 

To install gentoo in a system by going through all the setup steps interactively:

```bash
# curl, git and wget is needed
bash <(curl -s https://raw.githubusercontent.com/pedro-pereira-dev/gentoo-installer/refs/heads/main/web-install.sh)
```

To install gentoo in a system from a templated system configuration, a `hostname` should be passed as argument:

```bash
# curl, git and wget is needed
bash <(curl -s https://raw.githubusercontent.com/pedro-pereira-dev/gentoo-installer/refs/heads/main/web-install.sh) gentoo-laptop-msi-es
```
