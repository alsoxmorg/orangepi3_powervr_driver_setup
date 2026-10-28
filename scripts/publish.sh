#!/bin/bash
# Publish reviewed source files from a normal, GitHub-connected shell.
set -euo pipefail
base=$(cd -- "$(dirname -- "$(readlink -f -- "$0")")/.." && pwd)
if [ "$#" -ne 1 ]; then
  echo 'Usage: ./scripts/publish.sh git@github.com:OWNER/REPOSITORY.git' >&2
  exit 2
fi
case "$1" in
  https://github.com/*|git@github.com:*) ;;
  *) echo 'Expected a GitHub HTTPS or SSH repository URL.' >&2; exit 2 ;;
esac
destination="$base/work/github-publish"
mkdir -p "$base/work"
if [ -e "$destination" ]; then
  test -d "$destination/.git" || { echo "Not a Git checkout: $destination" >&2; exit 1; }
  remote=$(git -C "$destination" config --get remote.origin.url)
  test "$remote" = "$1" || { echo "Origin is $remote; use that URL or inspect the checkout first." >&2; exit 1; }
  test -z "$(git -C "$destination" status --porcelain)" || {
    echo "Checkout has uncommitted files: $destination; review/commit them before retrying." >&2; exit 1;
  }
  branch=$(git -C "$destination" symbolic-ref --quiet --short HEAD) || {
    echo 'Publishing checkout has a detached HEAD; inspect it first.' >&2; exit 1;
  }
  git -C "$destination" fetch origin
  if git -C "$destination" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    git -C "$destination" merge --ff-only "origin/$branch"
  fi
else
  git clone -- "$1" "$destination"
fi
python3 - "$base" "$destination" <<'PY'
from pathlib import Path
import shutil, subprocess, sys
source, target = map(Path, sys.argv[1:])
names = ['README.md', 'LICENSE', '.gitignore', 'install.sh', 'scripts',
         'metadata', 'patches', 'config', 'docs', 'tests', '.github']
# Delete only tracked release files removed from the authoritative source tree.
tracked = subprocess.check_output(['git', '-C', str(target), 'ls-files', '-z']).decode().split('\0')
for name in filter(None, tracked):
    path = Path(name)
    if path.parts[0] in names and not (source / path).exists():
        (target / path).unlink()
for name in names:
    path = source / name
    if path.is_dir():
        shutil.copytree(path, target / name, dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns('__pycache__'))
    else:
        shutil.copy2(path, target / name)
PY
git -C "$destination" add --all -- README.md LICENSE .gitignore install.sh scripts metadata patches config docs tests .github
if git -C "$destination" diff --cached --quiet; then
  echo 'No new source changes; pushing any previously committed updates.'
else
  git -C "$destination" commit -m 'Update experimental PowerVR driver source release'
fi
# Uses the user's configured Git identity and existing GitHub credentials.
# Normal push only: never force-push or overwrite remote history.
git -C "$destination" push origin HEAD
echo 'Published source release. No donor image, generated package or build tree was copied.'
