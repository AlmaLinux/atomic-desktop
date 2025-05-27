#!/usr/bin/env bash

set -xeuo pipefail

if [[ "${VARIANT}" == "gnome" ]]; then
    true

elif [[ "${VARIANT}" == "kde" ]]; then
    true
    # rm -rf /usr/share/plasma/look-and-feel/org.fedoraproject.fedora.desktop

    # sed -i \
    #     's,org.fedoraproject.fedora.desktop,org.kde.breezetwilight.desktop,g' \
    #     /usr/share/kde-settings/kde-profile/default/xdg/kdeglobals

    # sed -i \
    #     's,#Current=01-breeze-fedora,Current=breeze,g' \
    #     /etc/sddm.conf

else
    true

fi

rm -rf /usr/share/wallpapers/Fedora
rm -rf /usr/share/wallpapers/F4*
rm -rf /usr/share/backgrounds/f4*

dnf remove -y \
    console-login-helper-messages

dnf install -y \
    plymouth-theme-spinner


kver=$(cd /usr/lib/modules && echo * | awk '{print $1}')
dracut -vf /usr/lib/modules/$kver/initramfs.img $kver
