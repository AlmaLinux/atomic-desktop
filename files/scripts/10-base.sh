#!/usr/bin/env bash

set -xeuo pipefail

dnf install -y 'dnf-command(config-manager)' epel-release
dnf config-manager --set-enabled crb

# EPEL ships it's own epel-release package, let's make sure we've got that one
# We've got to do it this way because the package is named differently in x86_64_v2
dnf upgrade -y $(dnf repoquery --installed --qf '%{name}' --whatprovides epel-release)

dnf install -y system-reinstall-bootc
