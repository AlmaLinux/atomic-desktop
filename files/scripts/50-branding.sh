#!/usr/bin/env bash

set -xeuo pipefail

if [[ "${VARIANT}" == "gnome" ]]; then
    true

elif [[ "${VARIANT}" == "kde" ]]; then
    true
        
elif [[ "${VARIANT}" == "cosmic" ]]; then
    true

else
    true

fi

dnf remove -y \
    console-login-helper-messages

dnf install -y \
    plymouth-theme-spinner

kver=$(cd /usr/lib/modules && echo * | awk '{print $1}')
dracut -vf /usr/lib/modules/$kver/initramfs.img $kver
