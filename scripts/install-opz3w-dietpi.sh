#!/bin/bash
# Orange Pi Zero 3W / DietPi (Debian 13), vendor sun60iw2 kernel.
set -euo pipefail
export BOARD_ENV=opz3w
if [ "$#" = 0 ]; then set -- setup; fi
exec bash "$(dirname -- "$(readlink -f -- "$0")")/../install.sh" "$@"
