#!/bin/bash
# Orange Pi Zero 4 / Orange Pi Debian 13, current sun60iw2 kernel.
set -euo pipefail
export BOARD_ENV=opz4
if [ "$#" = 0 ]; then set -- setup; fi
exec bash "$(dirname -- "$(readlink -f -- "$0")")/../install.sh" "$@"
