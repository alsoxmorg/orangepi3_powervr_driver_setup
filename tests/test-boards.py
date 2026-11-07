"""Board resolution and generated preinst tests; no DRM/system writes required."""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

BASE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('boards', BASE / 'scripts/boards.py')
boards = importlib.util.module_from_spec(spec)
spec.loader.exec_module(boards)


class BoardTests(unittest.TestCase):
    def setUp(self):
        self.profiles = boards.load_profiles()

    def test_autodetect_both_profiles_with_soc_first(self):
        for alias in ('opz3w', 'opz4'):
            compatible = ['arm,sun60iw2p1', self.profiles[alias]['compatible'][0]]
            self.assertEqual(boards.resolve(self.profiles, '', compatible, True)[0], alias)

    def test_explicit_profile_is_not_a_hardware_override(self):
        with self.assertRaisesRegex(ValueError, 'does not match'):
            boards.resolve(self.profiles, 'opz4', ['xunlong,orangepi-zero3w'], True)
        self.assertEqual(boards.resolve(self.profiles, 'opz4', [], False)[0], 'opz4')

    def test_unknown_alias_and_unknown_or_ambiguous_machine(self):
        with self.assertRaises(ValueError):
            boards.resolve(self.profiles, 'zero4;echo bad', [], False)
        for compatible in ([], ['arm,sun60iw2p1'], ['xunlong,orangepi-zero3w', 'xunlong,orangepi-zero4']):
            with self.assertRaises(ValueError):
                boards.resolve(self.profiles, '', compatible)

    def test_zero4_is_not_reported_as_tested(self):
        self.assertEqual(self.profiles['opz4']['status'], 'experimental-unverified')
        self.assertIn('provisional', self.profiles['opz4']['compatible_status'])

    def test_binary_compatible_reader(self):
        with tempfile.TemporaryDirectory() as directory:
            p = Path(directory)/'compatible'
            p.write_bytes(b'xunlong,orangepi-zero3w\0arm,sun60iw2p1\0')
            self.assertEqual(boards.compatible_values(p), ['xunlong,orangepi-zero3w', 'arm,sun60iw2p1'])

    def test_low_ram_default_and_positive_override(self):
        self.assertEqual(boards.build_jobs('', 'MemAvailable: 700000 kB\n', 8), 1)
        self.assertEqual(boards.build_jobs('', 'MemAvailable: 1600000 kB\n', 8), 2)
        self.assertEqual(boards.build_jobs('', 'MemAvailable: 6000000 kB\n', 8), 4)
        self.assertEqual(boards.build_jobs('', 'MemAvailable: 6000000 kB\n', 2), 2)
        self.assertEqual(boards.build_jobs('6', '', 8), 6)
        for value in ('0', '-1', 'auto', '1;echo bad'):
            with self.assertRaises(ValueError): boards.build_jobs(value)

    def test_kernel_package_overrides_are_validated(self):
        result = boards.settings('opz4', self.profiles['opz4'],
                                 {'JOBS': '1', 'KERNEL_IMAGE_PACKAGE': 'linux-image-custom',
                                  'KERNEL_HEADERS_PACKAGE': 'linux-headers-custom'})
        self.assertEqual(result['KERNEL_IMAGE_PACKAGE'], 'linux-image-custom')
        with self.assertRaises(ValueError):
            boards.settings('opz4', self.profiles['opz4'], {'KERNEL_IMAGE_PACKAGE': 'bad; echo bad'})

    def test_generated_preinst_uses_nul_identifiers_and_rejects_mismatch(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            device = root/'compatible'
            bin_dir = root/'bin'; bin_dir.mkdir()
            uname = bin_dir/'uname'; uname.write_text('#!/bin/sh\necho aarch64\n'); uname.chmod(0o755)
            env = dict(os.environ, PATH=f'{bin_dir}:{os.environ["PATH"]}', BOARD_ENV='opz4')
            for alias, profile in self.profiles.items():
                script = root/'preinst'
                script.write_text(boards.preinst_guard(alias, profile).replace('/proc/device-tree/compatible', str(device)))
                subprocess.run(['sh', '-n', str(script)], check=True)
                for host in ('opz3w', 'opz4', 'unknown'):
                    identifier = self.profiles[host]['compatible'][0] if host in self.profiles else 'arm,sun60iw2p1'
                    device.write_bytes((identifier+'\0arm,sun60iw2p1\0').encode())
                    result = subprocess.run(['sh', str(script), 'upgrade'], env=env, capture_output=True)
                    self.assertEqual(result.returncode == 0, alias == host, result.stderr.decode())
                device.write_bytes((profile['compatible'][0]+'\0').encode())
                uname.write_text('#!/bin/sh\necho x86_64\n')
                self.assertNotEqual(subprocess.run(['sh', str(script)], env=env, capture_output=True).returncode, 0)
                uname.write_text('#!/bin/sh\necho aarch64\n')

    def test_shell_loader_exports_explicit_selection(self):
        for alias in ('opz3w', 'opz4'):
            env = dict(os.environ, BOARD_ENV=alias, JOBS='1')
            command = 'source scripts/board-env.sh; board_env_init; test "$BOARD_ENV" = "$1"; test "$JOBS" = 1'
            result = subprocess.run(['bash', '-euc', command, 'fixture', alias], cwd=BASE, env=env, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr.decode())


if __name__ == '__main__':
    unittest.main()
