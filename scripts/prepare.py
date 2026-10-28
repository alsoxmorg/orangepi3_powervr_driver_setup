#!/usr/bin/env python3
"""Extract verified GPU inputs from the pinned donor without mounting it."""
import hashlib
import json
import lzma
from pathlib import Path
import shutil
import struct
import subprocess
import sys

BASE = Path(__file__).resolve().parent.parent
WORK = BASE / 'work'
EXPECTED = '42fa0ac06b7beb5837457f373a7938857cf34f4b6c899f1a3785830d7b2b4265'
SOURCE = 'img-bxm-dkms-0.1.0-1'


def runtime_inputs():
    result = json.loads((BASE / 'metadata/runtime.json').read_text())
    result.update(json.loads((BASE / 'metadata/userland.json').read_text()))
    return result


def digest(path, algorithm='sha256'):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, algorithm).hexdigest()


def verify():
    for line in (BASE / 'metadata/source.md5sums').read_text().splitlines():
        expected, path = line.split(None, 1)
        if path.startswith('usr/src/'):
            local = WORK / 'source' / path.removeprefix('usr/src/')
            if digest(local, 'md5') != expected:
                raise RuntimeError(f'Source verification failed: {path}')
    for path, expected in runtime_inputs().items():
        if digest(WORK / 'runtime' / path) != expected:
            raise RuntimeError(f'Runtime verification failed: {path}')
    print('Verified source and runtime contents.')


def main():
    if sys.argv[1:] == ['--verify']:
        verify()
        return
    if len(sys.argv) != 2:
        raise SystemExit('Usage: prepare.py DONOR.img.xz | --verify')
    donor = Path(sys.argv[1]).resolve()
    if digest(donor) != EXPECTED:
        raise SystemExit('Donor hash differs from the tested image. Refusing extraction.')
    metadata = json.loads((BASE / 'metadata/donor.json').read_text())
    if digest(donor, 'sha512') != metadata['sha512']:
        raise SystemExit('Donor differs from the published Radxa SHA512 checksum.')
    debugfs = shutil.which('debugfs') or '/usr/sbin/debugfs'
    if not Path(debugfs).is_file():
        raise SystemExit('Install e2fsprogs first.')
    if (WORK / 'source').exists() or (WORK / 'runtime').exists():
        raise SystemExit('Prepared inputs exist. Use --verify or move work/ aside first.')
    WORK.mkdir(exist_ok=True)
    image = WORK / 'donor.img'
    rootfs = WORK / 'rootfs.ext4'
    print('Decompressing donor (approximately 6.5 GiB)...', flush=True)
    with lzma.open(donor, 'rb') as src, image.open('wb') as dst:
        shutil.copyfileobj(src, dst, 8 * 1024 * 1024)
    with image.open('rb') as src:
        src.seek(512)
        header = src.read(512)
        if header[:8] != b'EFI PART':
            raise RuntimeError('Expected GPT image')
        table, count, entry_size = struct.unpack_from('<QII', header, 72)
        if count > 4096 or entry_size != 128:
            raise RuntimeError('Unexpected GPT layout')
        src.seek(table * 512 + 2 * entry_size)
        entry = src.read(entry_size)
        start, end = struct.unpack_from('<QQ', entry, 32)
        offset, size = start * 512, (end - start + 1) * 512
        if (offset, size) != (348127232, 6568624640):
            raise RuntimeError('Unexpected donor rootfs partition')
        src.seek(offset)
        with rootfs.open('wb') as dst:
            remaining = size
            while remaining:
                data = src.read(min(8 * 1024 * 1024, remaining))
                if not data:
                    raise RuntimeError('Truncated partition')
                # Preserve holes to reduce writes on the SD card.
                if data.count(0) == len(data):
                    dst.seek(len(data), 1)
                else:
                    dst.write(data)
                remaining -= len(data)
            dst.truncate(size)
    image.unlink()
    (WORK / 'source').mkdir()
    commands = [f'rdump /usr/src/{SOURCE} source']
    for path in runtime_inputs():
        dest = WORK / 'runtime' / path
        dest.parent.mkdir(parents=True, exist_ok=True)
        commands.append(f'dump /{path} runtime/{path}')
    batch = WORK / 'extract.commands'
    batch.write_text('\n'.join(commands) + '\n')
    result = subprocess.run([debugfs, '-f', batch.name, rootfs.name], cwd=WORK,
                            text=True, capture_output=True)
    (WORK / 'extract.log').write_text(result.stdout + result.stderr)
    # debugfs may warn about preserving root ownership as an ordinary user;
    # validate all extracted contents independently rather than trust exit status.
    verify()
    rootfs.unlink()
    print('Prepared inputs in work/. No system files changed.')


if __name__ == '__main__':
    main()
