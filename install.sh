#!/bin/bash

# gets this script directory for relative imports
SCRIPT_ROOT_DIR=$(dirname $(readlink -f $0))
HOSTS_DIR=${SCRIPT_ROOT_DIR}/hosts
STEPS_DIR=${SCRIPT_ROOT_DIR}/steps

# gets host setup file, if it exists
HOST_SETUP=${HOSTS_DIR}/$1.props

# runs installation
[[ ! -f ${HOST_SETUP} ]] && source ${STEPS_DIR}/00-intro.sh && source ${STEPS_DIR}/01-configuring-system.sh
[[ -f ${HOST_SETUP} ]] && source ${STEPS_DIR}/01-configuring-system.sh ${HOST_SETUP}
source ${STEPS_DIR}/02-preparing-disks.sh
source ${STEPS_DIR}/03-installing-stage.sh
source ${STEPS_DIR}/04-chroot.sh
