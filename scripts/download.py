#!/usr/bin/env python3
"""Fetch the pinned official donor; never execute downloaded code."""
import hashlib
import json
from pathlib import Path
import subprocess

BASE = Path(__file__).resolve().parent.parent


def verified(path, metadata):
    if not path.is_file():
        return False
    for algorithm in ('sha256', 'sha512'):
        with path.open('rb') as stream:
            if hashlib.file_digest(stream, algorithm).hexdigest() != metadata[algorithm]:
                return False
    return True


def main():
    metadata = json.loads((BASE / 'metadata/donor.json').read_text())
    directory = BASE / 'work/downloads'
    directory.mkdir(parents=True, exist_ok=True)
    destination = directory / metadata['filename']
    if destination.exists():
        if not verified(destination, metadata):
            raise SystemExit('Cached donor has a wrong hash. Move it aside before retrying.')
    else:
        partial = destination.with_suffix(destination.suffix + '.part')
        subprocess.run(['curl', '--fail', '--location', '--retry', '3',
                        '--proto', '=https', '--proto-redir', '=https',
                        '--output', str(partial), metadata['url']], check=True)
        if not verified(partial, metadata):
            raise SystemExit('Donor checksum failed; refusing to extract it.')
        partial.replace(destination)
    print(destination)


if __name__ == '__main__':
    main()
