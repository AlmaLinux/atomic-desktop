#!/usr/bin/env bash

set -xeuo pipefail

dnf install -y 'dnf-command(config-manager)' epel-release
dnf config-manager --set-enabled crb

# EPEL ships it's own epel-release package, let's make sure we've got that one
dnf upgrade -y --best --allowerasing epel-release

dnf install -y system-reinstall-bootc
