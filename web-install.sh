#!/bin/bash

# checks required dependencies
function check() { [[ -z $(command -v $1) ]] && echo "Missing command: $1" && exit 1; }
check git
check wget

# clones project and executes it
git clone https://github.com/pedro-pereira-dev/gentoo-installer
gentoo-installer/install.sh $1 2>&1 | tee ./install.log
