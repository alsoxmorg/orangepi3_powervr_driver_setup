"""Exercise recovery/logging without a compositor, DRM device, or screen change."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

GUARD = Path(__file__).resolve().parents[1] / 'scripts/run-hardware-session.py'


class SessionGuardTests(unittest.TestCase):
    def run_session(self, source, duration=0):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / 'session.log'
            result = subprocess.run(
                [sys.executable, str(GUARD), '--log', str(log), '--timeout', str(duration),
                 '--', sys.executable, '-u', '-c', source],
                capture_output=True, timeout=10, check=False)
            return result, log.read_text()

    def test_preserves_output_and_records_normal_exit(self):
        result, log = self.run_session('import sys; print("stdout"); print("stderr", file=sys.stderr)')
        self.assertEqual(result.returncode, 0)
        self.assertIn('stdout', log)
        self.assertIn('stderr', log)
        self.assertIn('compositor exit 0; reason=normal exit', log)

    def test_output_failure_stops_only_launched_process(self):
        result, log = self.run_session(
            'import time; print("Unable to find valid config with output HDMI-A-1, disabling"); time.sleep(60)')
        self.assertEqual(result.returncode, 1)
        self.assertIn('Sway could not configure the physical output', log)
        self.assertNotIn('compositor exit 0;', log)

    def test_failure_message_across_reads(self):
        result, log = self.run_session(
            'import sys,time; sys.stdout.write("Unable to find valid config "); sys.stdout.flush(); '
            'time.sleep(.3); print("with output HDMI-A-1, disabling"); time.sleep(60)')
        self.assertEqual(result.returncode, 1)
        self.assertIn('stopping compositor PID', log)

    def test_quiet_process_is_bounded(self):
        result, log = self.run_session('import time; time.sleep(60)', duration=.4)
        self.assertEqual(result.returncode, 0)
        self.assertIn('0.4-second test finished', log)

    def test_early_failure_is_not_timeout_success(self):
        result, log = self.run_session('raise SystemExit(7)', duration=60)
        self.assertEqual(result.returncode, 1)
        self.assertIn('compositor exit 7', log)

    def test_signal_exit_is_identified(self):
        result, log = self.run_session('import os,signal; os.kill(os.getpid(), signal.SIGTERM)')
        self.assertEqual(result.returncode, 1)
        self.assertIn('reason=terminated by SIGTERM', log)


if __name__ == '__main__':
    unittest.main()
