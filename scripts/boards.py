#!/usr/bin/env python3
"""Resolve BOARD_ENV and generate standalone target-board installation guards."""
import argparse
import json
import os
from pathlib import Path
import re
import shlex
import sys

MANIFEST = Path(__file__).resolve().parents[1] / 'metadata/boards.json'
DEVICE_TREE = Path('/proc/device-tree/compatible')


def load_profiles(path=MANIFEST):
    profiles = json.loads(path.read_text())
    for alias, profile in profiles.items():
        if not re.fullmatch(r'[a-z][a-z0-9]*', alias):
            raise ValueError(f'Invalid board alias: {alias}')
        if not profile['compatible'] or any(not re.fullmatch(r'[a-zA-Z0-9,._+-]+', item)
                                            for item in profile['compatible']):
            raise ValueError(f'Invalid compatible identifiers: {alias}')
    return profiles


def compatible_values(path=DEVICE_TREE):
    try:
        return path.read_bytes().decode('ascii').rstrip('\0').split('\0')
    except FileNotFoundError:
        return []


def matches(profile, compatible):
    return bool(set(profile['compatible']).intersection(compatible))


def resolve(profiles, requested, compatible, check_host=False):
    if requested:
        if requested not in profiles:
            raise ValueError(f'Unknown BOARD_ENV={requested!r}; choose {", ".join(profiles)}')
        alias = requested
    else:
        found = [name for name, profile in profiles.items() if matches(profile, compatible)]
        if len(found) != 1:
            raise ValueError(f'Cannot uniquely detect supported board from {compatible!r}; '
                             f'choose BOARD_ENV from {", ".join(profiles)} after verifying the device tree')
        alias = found[0]
    if check_host and not matches(profiles[alias], compatible):
        raise ValueError(f'BOARD_ENV={alias} does not match device-tree compatible {compatible!r}. '
                         'This selection does not bypass hardware validation.')
    return alias, profiles[alias]


def build_jobs(requested, meminfo=None, cpu_count=None):
    if requested:
        if not re.fullmatch(r'[1-9][0-9]*', requested):
            raise ValueError('JOBS must be a positive integer')
        return int(requested)
    if meminfo is None:
        meminfo = Path('/proc/meminfo').read_text()
    available = re.search(r'^MemAvailable:\s+(\d+)\s+kB$', meminfo, re.M)
    memory_jobs = int(available[1]) // (768 * 1024) if available else 1
    return max(1, min(4, cpu_count or os.cpu_count() or 1, memory_jobs))


def settings(alias, profile, environ):
    image = environ.get('KERNEL_IMAGE_PACKAGE') or profile['kernel_image_package']
    headers = environ.get('KERNEL_HEADERS_PACKAGE') or profile['kernel_headers_package']
    for package in (image, headers):
        if not re.fullmatch(r'[a-z0-9][a-z0-9+.-]+', package):
            raise ValueError(f'Invalid kernel package name: {package!r}')
    return {'BOARD_ENV': alias, 'BOARD_NAME': profile['name'], 'BOARD_STATUS': profile['status'],
            'KERNEL_IMAGE_PACKAGE': image, 'KERNEL_HEADERS_PACKAGE': headers,
            'JOBS': str(build_jobs(environ.get('JOBS')))}


def preinst_guard(alias, profile):
    cases = '|'.join(shlex.quote(item) for item in profile['compatible'])
    return f'''#!/bin/sh
set -e
# Generated from boards.json for BOARD_ENV={alias}; no Python needed at install time.
matched=no
if [ -r /proc/device-tree/compatible ]; then
  identifiers=$(tr '\\000' '\\n' < /proc/device-tree/compatible)
  old_ifs=$IFS
  IFS='
'
  for identifier in $identifiers; do
    case "$identifier" in {cases}) matched=yes ;; esac
  done
  IFS=$old_ifs
fi
if [ "$matched" != yes ] || [ "$(uname -m)" != aarch64 ]; then
  echo {shlex.quote(f'This package targets {profile["name"]} ({alias}); device tree/architecture does not match.')} >&2
  exit 1
fi
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--list', action='store_true')
    parser.add_argument('--board', default=os.environ.get('BOARD_ENV', ''))
    parser.add_argument('--check-host', action='store_true')
    parser.add_argument('--env-lines', action='store_true')
    parser.add_argument('--preinst', action='store_true')
    args = parser.parse_args()
    profiles = load_profiles()
    if args.list:
        for alias, profile in profiles.items():
            print(f'{alias}: {profile["name"]} [{profile["status"]}]')
        return
    alias, profile = resolve(profiles, args.board, compatible_values(), args.check_host)
    if args.preinst:
        print(preinst_guard(alias, profile), end='')
        return
    resolved = settings(alias, profile, os.environ)
    if args.env_lines:
        for key, value in resolved.items():
            print(f'{key}\t{value}')
    else:
        print(json.dumps({**resolved, 'compatible': profile['compatible'],
                          'compatible_status': profile['compatible_status']}, indent=2))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError) as error:
        sys.exit(f'Board configuration: {error}')
