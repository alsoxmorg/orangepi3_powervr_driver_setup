#!/bin/bash
set -euo pipefail
base=$(cd -- "$(dirname -- "$(readlink -f -- "$0")")/.." && pwd)
if [ "$#" -ne 1 ]; then echo 'Usage: build-path-shim.sh OUTPUT.so' >&2; exit 2; fi
output=$1
mkdir -p -- "$(dirname -- "$output")"
temporary=$(mktemp "${output}.XXXXXX")
trap 'rm -f -- "$temporary"' EXIT
gcc -std=c11 -O2 -Wall -Wextra -Werror -fPIC -shared \
  "$base/scripts/egl-dri-path.c" -ldl -o "$temporary"
chmod 644 "$temporary"
mv -f -- "$temporary" "$output"
