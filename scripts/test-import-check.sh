#!/bin/bash
# Compile and test process-local import validation without DRM or a display.
set -euo pipefail
base=$(cd -- "$(dirname -- "$(readlink -f -- "$0")")/.." && pwd)
temporary=$(mktemp -d)
trap 'rm -rf -- "$temporary"' EXIT
cc -std=c11 -O2 -Wall -Wextra -Werror -fPIC -shared \
  "$base/scripts/wlroots-egl-import-check.c" -ldl -o "$temporary/helper.so"
cc -std=c11 -O2 -Wall -Wextra -Werror -fPIC -shared -DFIXTURE_LIBRARY \
  "$base/tests/import-check-fixture.c" -o "$temporary/libfixture.so"
cc -std=c11 -O2 -Wall -Wextra -Werror "$base/tests/import-check-fixture.c" \
  -L"$temporary" -lfixture -Wl,-rpath,"$temporary" -o "$temporary/test"
LD_PRELOAD="$temporary/helper.so" "$temporary/test"
