"""Installer safety/flow tests: temporary packages and mock commands, no root/network."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

BASE = Path(__file__).resolve().parents[1]
SUPPORT = BASE / 'scripts/install-support.sh'


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.log = self.root / 'actions.jsonl'
        self.env = dict(os.environ, PATH=f'{self.bin}:{os.environ["PATH"]}',
                        ACTION_LOG=str(self.log), BOARD_ENV='opz4',
                        KERNEL_HEADERS_PACKAGE='linux-headers-current-sun60iw2')
        self.env.pop('KERNEL_HEADERS_DEB', None)
        self.mock('dpkg-query', 'exit 1\n')

    def mock(self, name, body):
        path = self.bin / name
        path.write_text('#!/bin/bash\n' + body)
        path.chmod(0o755)

    def run_helper(self, command, **env):
        return subprocess.run(['bash', '-euc', f'source "$1"; {command}', 'test', str(SUPPORT)],
                              cwd=self.root, env=dict(self.env, **env), text=True, capture_output=True)

    def package(self, name='linux-headers-current-sun60iw2', version='1.0.0', arch='arm64'):
        stage = self.root / f'package-{name}-{version}-{arch}'
        (stage / 'DEBIAN').mkdir(parents=True)
        (stage / 'DEBIAN/control').write_text(
            f'Package: {name}\nVersion: {version}\nArchitecture: {arch}\n'
            'Maintainer: Test <test@example.invalid>\nDescription: header selection test\n')
        output = self.root / f'{name}_{version}_{arch}.deb'
        subprocess.run(['dpkg-deb', '--build', str(stage), str(output)],
                       check=True, capture_output=True)
        return output

    def test_repo_headers_are_pinned_to_exact_image_version(self):
        result = self.run_helper('headers_install_target 1.0.0 /nonexistent')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), 'linux-headers-current-sun60iw2=1.0.0')

    def test_local_headers_with_spaces_and_exact_identity(self):
        package = self.package()
        spaced = self.root / 'trusted local headers.deb'
        package.rename(spaced)
        result = self.run_helper('headers_install_target 1.0.0', KERNEL_HEADERS_DEB=str(spaced))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), str(spaced))

    def test_wrong_header_package_version_or_architecture_is_rejected(self):
        for name, version, arch in (('linux-headers-other', '1.0.0', 'arm64'),
                                    ('linux-headers-current-sun60iw2', '2.0.0', 'arm64'),
                                    ('linux-headers-current-sun60iw2', '1.0.0', 'amd64')):
            package = self.package(name, version, arch)
            result = self.run_helper('headers_install_target 1.0.0', KERNEL_HEADERS_DEB=str(package))
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('must match', result.stderr)

    def test_zero4_finds_shipped_headers_but_zero3w_uses_apt(self):
        self.package()
        result = self.run_helper('headers_install_target 1.0.0 "$LOCAL_HEADERS"', LOCAL_HEADERS=str(self.root))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(result.stdout.strip().endswith('.deb'))
        result = self.run_helper('headers_install_target 1.0.0 "$LOCAL_HEADERS"',
                                 LOCAL_HEADERS=str(self.root), BOARD_ENV='opz3w')
        self.assertIn('=1.0.0', result.stdout)

    def test_installed_headers_are_not_reinstalled(self):
        self.mock('dpkg-query', "printf 'install ok installed\\t1.0.0'\n")
        result = self.run_helper('headers_install_target 1.0.0 /nonexistent')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, '')
        self.mock('dpkg-query', "printf 'deinstall ok config-files\\t1.0.0'\n")
        result = self.run_helper('headers_install_target 1.0.0 /nonexistent')
        self.assertIn('=1.0.0', result.stdout)

    def test_native_os_and_architecture_checks(self):
        release = self.root / 'os-release'
        release.write_text('ID=debian\nVERSION_ID=13\n')
        self.mock('uname', 'echo aarch64\n')
        self.mock('dpkg', 'echo arm64\n')
        result = self.run_helper('require_native_host "$RELEASE"', RELEASE=str(release))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.mock('uname', 'echo x86_64\n')
        self.assertNotEqual(self.run_helper('require_native_host "$RELEASE"', RELEASE=str(release)).returncode, 0)
        self.mock('uname', 'echo aarch64\n')
        release.write_text('ID=debian\nVERSION_ID=12\n')
        self.assertNotEqual(self.run_helper('require_native_host "$RELEASE"', RELEASE=str(release)).returncode, 0)

    def test_package_records_cannot_select_other_board_or_escape_dist(self):
        dist = self.root / 'dist'
        dist.mkdir()
        record = dist / 'core-package-opz4.path'
        for name, accepted in (
            ('orangepi-zero3w-powervr_24.2.6603887-5+opz4.kernel1.0.0_arm64.deb', True),
            ('orangepi-zero3w-powervr_24.2.6603887-5+opz3w.kernel1.0.0_arm64.deb', False),
            ('../outside_arm64.deb', False)):
            (dist / Path(name).name).touch()
            record.write_text(name + '\n')
            result = self.run_helper('core_package_path')
            self.assertEqual(result.returncode == 0, accepted, result.stderr)

    def test_permissions_preserve_existing_groups_and_reject_root(self):
        self.mock('id', 'if [ "$3" = root ]; then echo 0; else echo 1001; fi\n')
        self.mock('getent', 'exit 0\n')
        self.mock('usermod', 'printf "%s\\n" "$*" > "$ACTION_LOG"\n')
        result = self.run_helper('configure_access alice')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text().strip(), '-aG video,render -- alice')
        self.assertIn('TTY completely', result.stdout)
        self.assertNotEqual(self.run_helper('configure_access root').returncode, 0)

    def test_platform_entrypoints_select_profile_and_forward_commands(self):
        scripts = self.root / 'scripts'
        scripts.mkdir()
        (self.root / 'install.sh').write_text('printf "%s:%s\\n" "$BOARD_ENV" "$*"\n')
        for filename, alias in (('install-opz3w-dietpi.sh', 'opz3w'), ('install-opz4-debian.sh', 'opz4')):
            target = scripts / filename
            shutil.copy2(BASE / 'scripts' / filename, target)
            for args, expected in (([], 'setup'), (['build', '/tmp/donor image.xz'], 'build /tmp/donor image.xz')):
                result = subprocess.run(['bash', str(target), *args], env=self.env, text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), f'{alias}:{expected}')

    def test_setup_order_and_build_failure_stops_before_install(self):
        # Exercise the real setup branch, mocking only child actions and host checks.
        scripts = self.root / 'scripts'
        scripts.mkdir()
        shutil.copy2(BASE / 'install.sh', self.root / 'install.sh')
        (scripts / 'board-env.sh').write_text('''board_env_init() {
export BOARD_ENV=${BOARD_ENV:-opz4} ARCH=arm64 BOARD_NAME=Test BOARD_STATUS=tested
export KERNEL_IMAGE_PACKAGE=linux-image-test KERNEL_HEADERS_PACKAGE=linux-headers-test
}
''')
        (scripts / 'install-support.sh').write_text('require_native_host() { :; }\n')
        self.mock('id', 'if [ "$1" = -u ]; then echo 1001; else echo alice; fi\n')
        self.mock('sudo', 'exec "$@"\n')
        self.mock('bash', '''python3 - "$@" <<'PY'
import json, os, sys
with open(os.environ['ACTION_LOG'], 'a') as stream:
    stream.write(json.dumps(sys.argv[2:])+'\\n')
if len(sys.argv) > 2 and sys.argv[2] == os.environ.get('FAIL_STEP'):
    sys.exit(7)
PY
''')
        for alias in ('opz3w', 'opz4'):
            for fail in ('', 'build'):
                self.log.unlink(missing_ok=True)
                result = subprocess.run(['/bin/bash', str(self.root / 'install.sh'), 'setup', '/tmp/donor image.xz'],
                                        env=dict(self.env, BOARD_ENV=alias, FAIL_STEP=fail), text=True, capture_output=True)
                actions = [json.loads(line) for line in self.log.read_text().splitlines()]
                expected = [['deps'], ['test-tools'], ['build', '/tmp/donor image.xz']]
                if not fail:
                    expected += [['userland'], ['install-all'], ['access', 'alice'], ['verify']]
                self.assertEqual(actions, expected)
                self.assertEqual(result.returncode, 7 if fail else 0, result.stderr)


if __name__ == '__main__':
    unittest.main()
