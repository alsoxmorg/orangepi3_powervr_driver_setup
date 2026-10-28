#!/usr/bin/env python3
"""Log only the launched compositor, and stop it on output setup failure."""
import argparse
import os
from pathlib import Path
import selectors
import signal
import subprocess
import sys
import time


def run(command, log_path, duration):
    with log_path.open('ab', buffering=0) as log:
        def record(data):
            log.write(data)
            os.fsync(log.fileno())

        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        stop_reason = None
        stop_at = None
        exited_at = None
        started = time.monotonic()

        def stop(reason):
            nonlocal stop_reason, stop_at
            if stop_reason is None:
                stop_reason, stop_at = reason, time.monotonic()
                record(f'\nSession guard: {reason}; stopping compositor PID {process.pid}\n'.encode())
                if process.poll() is None:
                    process.terminate()

        previous = {}
        for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            previous[sig] = signal.signal(sig, lambda number, frame: stop(f'received signal {number}'))
        selector = selectors.DefaultSelector()
        selector.register(process.stdout, selectors.EVENT_READ)
        tail = b''
        try:
            while True:
                now = time.monotonic()
                if duration and now - started >= duration:
                    stop(f'{duration:g}-second test finished')
                if stop_at is not None and now - stop_at >= 5 and process.poll() is None:
                    process.kill()
                if process.poll() is not None:
                    if exited_at is None:
                        exited_at = now
                    if not selector.get_map() or now - exited_at >= 1:
                        break
                for key, _ in selector.select(timeout=0.2):
                    chunk = os.read(key.fileobj.fileno(), 65536)
                    if not chunk:
                        selector.unregister(key.fileobj)
                        continue
                    record(chunk)
                    evidence = tail + chunk
                    if b'Unable to find valid config with output' in evidence:
                        stop('Sway could not configure the physical output')
                    tail = evidence[-256:]
            result = process.wait()
            if result < 0:
                exit_reason = f'terminated by {signal.Signals(-result).name}'
            elif result:
                exit_reason = f'exited with status {result}'
            else:
                exit_reason = 'normal exit'
            record(f'\nSession guard: compositor exit {result}; reason={stop_reason or exit_reason}\n'.encode())
        finally:
            selector.close()
            process.stdout.close()
            for sig, handler in previous.items():
                signal.signal(sig, handler)
            if process.poll() is None:
                process.terminate()
        if stop_reason:
            print(f'{stop_reason}. Log: {log_path}', file=sys.stderr)
        if stop_reason:
            return 0 if stop_reason == f'{duration:g}-second test finished' else 1
        return 0 if result == 0 else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--log', type=Path, required=True)
    parser.add_argument('--timeout', type=float, default=0)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command or args.timeout < 0:
        parser.error('a command and a nonnegative timeout are required')
    try:
        sys.exit(run(command, args.log, args.timeout))
    except OSError as error:
        sys.exit(f'Session guard: {error}')
