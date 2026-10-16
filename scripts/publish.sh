#!/bin/bash
# Publish reviewed source files from a normal, GitHub-connected shell.
set -euo pipefail
base=$(cd -- "$(dirname -- "$(readlink -f -- "$0")")/.." && pwd)
if [ "$#" -ne 1 ]; then
  echo 'Usage: ./scripts/publish.sh https://github.com/OWNER/REPOSITORY.git' >&2
  exit 2
fi
case "$1" in
  https://github.com/*|git@github.com:*) ;;
  *) echo 'Expected a GitHub HTTPS or SSH repository URL.' >&2; exit 2 ;;
esac
destination="$base/work/github-publish"
test ! -e "$destination" || { echo "Checkout already exists: $destination; inspect it before retrying." >&2; exit 1; }
mkdir -p "$base/work"
git clone -- "$1" "$destination"
python3 - "$base" "$destination" <<'PY'
from pathlib import Path
import shutil, sys
source, target = map(Path, sys.argv[1:])
for name in ['README.md', 'LICENSE', '.gitignore', 'install.sh', 'scripts',
             'metadata', 'patches', 'config', 'docs', '.github']:
    path = source / name
    if path.is_dir():
        shutil.copytree(path, target / name, dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns('__pycache__'))
    else:
        shutil.copy2(path, target / name)
PY
git -C "$destination" add -- README.md LICENSE .gitignore install.sh scripts metadata patches config docs .github
if git -C "$destination" diff --cached --quiet; then
  echo 'No source changes to publish.'
  exit 0
fi
# Uses the user's configured Git identity and existing GitHub credentials.
# Normal push only: never force-push or overwrite remote history.
git -C "$destination" commit -m 'Add experimental Orange Pi Zero 3W PowerVR source release'
git -C "$destination" push origin HEAD
echo 'Published source release. No donor image, generated package or build tree was copied.'
