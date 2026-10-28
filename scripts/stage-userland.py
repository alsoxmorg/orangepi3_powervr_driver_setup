#!/usr/bin/env python3
"""Verify and stage the legacy vendor EGL/GBM stack without system changes."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile

BASE = Path(__file__).resolve().parent.parent


def stage(source, target):
    manifest = json.loads((BASE / 'metadata/userland.json').read_text())
    for name, expected in manifest.items():
        path = source / name
        if not path.is_file():
            raise SystemExit(f'Missing {path}; prepare the full donor inputs first.')
        with path.open('rb') as stream:
            actual = hashlib.file_digest(stream, 'sha256').hexdigest()
        if actual != expected:
            raise SystemExit(f'Vendor userland checksum mismatch: {name}')
    lib = target / 'lib'
    (lib / 'dri').mkdir(parents=True, exist_ok=True)
    for name in manifest:
        relative = Path(name).relative_to('usr/local/lib')
        destination = lib / relative
        if destination.is_file():
            with destination.open('rb') as stream:
                if hashlib.file_digest(stream, 'sha256').hexdigest() == manifest[name]:
                    continue
        # Replace atomically: do not truncate a library a test may have mapped.
        handle, temporary = tempfile.mkstemp(dir=destination.parent)
        os.close(handle)
        try:
            shutil.copy2(source / name, temporary)
            os.replace(temporary, destination)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
    aliases = {
        'libEGL.so': 'libEGL.so.1', 'libEGL.so.1': 'libEGL.so.1.0.0',
        'libGLESv1_CM.so': 'libGLESv1_CM.so.1', 'libGLESv1_CM.so.1': 'libGLESv1_CM.so.1.1.0',
        'libGLESv2.so': 'libGLESv2.so.2', 'libGLESv2.so.2': 'libGLESv2.so.2.0.0',
        'libgbm.so': 'libgbm.so.1', 'libgbm.so.1': 'libgbm.so.1.0.0',
        'libglapi.so': 'libglapi.so.0', 'libglapi.so.0': 'libglapi.so.0.0.0',
        'dri/sunxi-drm_dri.so': 'pvr_dri.so', 'dri/swrast_dri.so': 'pvr_dri.so',
    }
    for name, destination in aliases.items():
        path = lib / name
        if path.is_symlink():
            if os.readlink(path) == destination:
                continue
            path.unlink()
        elif path.exists():
            raise SystemExit(f'Refusing to replace non-symlink alias: {path}')
        path.symlink_to(destination)
    print(f'Verified and staged EGL/GLES/GBM/DRI in {target}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--from', dest='source', type=Path, default=BASE / 'work/runtime')
    parser.add_argument('--output', type=Path, default=BASE / 'work/userland-runtime')
    args = parser.parse_args()
    stage(args.source.resolve(), args.output.resolve())
