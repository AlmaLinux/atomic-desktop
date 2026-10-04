#!/usr/bin/env bash

set -xeuo pipefail

# Image cleanup
# Specifically called by build.sh

# Image-layer cleanup
shopt -s extglob

dnf clean all

rm -rf /.gitkeep /var /boot
mkdir -p /boot /var

# Make /usr/local writeable, unless the base image already did it
if [[ ! -L /usr/local ]]; then
    mv /usr/local /var/usrlocal
    ln -s /var/usrlocal /usr/local
fi
