#!/usr/bin/env bash

set -xeuo pipefail

dnf install -y \
    @core \
    @fonts \
    @guest-desktop-agents \
    @hardware-support \
    @input-methods \
    @multimedia \
    @networkmanager-submodules \
    @print-client \
    @standard

if [[ "${VARIANT}" == "gnome" ]]; then
    # aarch64 doesn't have @workstation group
    if [[ "${TARGETARCH}" == "arm64" ]]; then
        dnf install -y \
            @gnome-desktop \
            @internet-browser \
            @workstation-product
    else
        dnf install -y \
            @"Workstation"
    fi

    systemctl enable gdm

elif [[ "${VARIANT}" == "kde" ]]; then
    dnf install -y \
        --exclude=plasma-discover-packagekit \
        @"KDE Plasma Workspaces" \
        gwenview \
        okular

    systemctl enable plasmalogin

elif [[ "${VARIANT}" == "cosmic" ]]; then
    # workaround: cosmic-greeter requires fprintd-pam but for aarch64 it's only in devel repo
    if [[ "${TARGETARCH}" == "arm64" && ! $(dnf repoinfo devel -q | grep enabled) ]]; then
        dnf install -y almalinux-release-devel
        dnf config-manager --set-disabled devel
        dnf install -y fprintd-pam --enablerepo=devel
    fi

    dnf copr enable -y "ligenix/enterprise-cosmic" "rhel+epel-10-$(uname -m)"
    dnf install -y \
        cosmic-desktop

    systemctl enable cosmic-greeter

else
    true

fi

systemctl set-default graphical.target

dnf -y remove \
    setroubleshoot
