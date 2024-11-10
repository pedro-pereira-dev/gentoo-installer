#!/bin/bash

# checks if dependecies are installed
[[ -z $(command -v git) ]] && [[ -z $(command -v wget) ]] && echo 'Missing dependencies: git and/or wget' && exit 1
# clones project and executes it
git clone https://github.com/pedro-pereira-dev/gentoo-installer
gentoo-installer/install.sh $1 2>&1 | tee ./install.log
