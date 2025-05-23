#!/usr/bin/env bash

set -xeuo pipefail

# Example of how you start customizing the image

dnf install -y 'dnf-command(config-manager)'
dnf config-manager --set-enabled crb

if [[ "${VARIANT}" == "gnome" ]]; then
    echo "Installing gnome"
elif [[ "${VARIANT}" == "kde" ]]; then
    echo "Installing kde"
else
    echo "Neutral variant"
fi
