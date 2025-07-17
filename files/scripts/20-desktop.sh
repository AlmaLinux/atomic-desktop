#!/usr/bin/env bash

set -xeuo pipefail

if [[ "${VARIANT}" == "gnome" ]]; then
    dnf install -y \
        @"Workstation"

    systemctl enable gdm

elif [[ "${VARIANT}" == "kde" ]]; then
    dnf install -y \
        --exclude=plasma-discover-packagekit \
        @"KDE Plasma Workspaces"

    systemctl enable sddm

else
    true

fi

systemctl set-default graphical.target

dnf -y remove \
    setroubleshoot
