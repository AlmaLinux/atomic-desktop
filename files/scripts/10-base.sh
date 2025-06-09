#!/usr/bin/env bash

set -xeuo pipefail

dnf install -y 'dnf-command(config-manager)'
dnf config-manager --set-enabled crb
