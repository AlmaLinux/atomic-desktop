#!/usr/bin/env bash

set -xeuo pipefail

dnf install -y \
    epel-release

crb enable
