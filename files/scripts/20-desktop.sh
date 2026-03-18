#!/usr/bin/env bash

set -xeuo pipefail

if [[ "${VARIANT}" == "gnome" ]]; then
    # aarch64 doesn't have @workstation group
    if [[ "${TARGETARCH}" == "arm64" ]]; then
        dnf install -y \
            @core \
            @fonts \
            @gnome-desktop \
            @guest-desktop-agents \
            @hardware-support \
            @internet-browser \
            @multimedia \
            @networkmanager-submodules \
            @print-client \
            @standard \
            @workstation-product
    else
        dnf install -y \
            @"Workstation"
    fi

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
