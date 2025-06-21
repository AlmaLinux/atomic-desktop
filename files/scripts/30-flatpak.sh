#!/usr/bin/env bash

set -xeuo pipefail

systemctl enable -f system-flatpak-setup.timer
systemctl enable -f --global user-flatpak-setup.timer
