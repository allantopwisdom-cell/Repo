import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class MaintainerScripts(unittest.TestCase):
    def run_script(self, script, action, launch_status=0, kill_status=0,
                   launch_present=True, kill_present=True):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            log = folder / 'calls'
            for name, present in (('launchctl', launch_present), ('killall', kill_present),
                                  ('defaults', True), ('notify_post', True),
                                  ('sbreload', True), ('ldrestart', True)):
                if not present:
                    continue
                program = folder / name
                status = {'launchctl': launch_status, 'killall': kill_status}.get(name, 0)
                program.write_text('#!/bin/sh\nprintf "%s\\n" "' + name + ' $*" >> "$CALL_LOG"\n'
                                   + 'echo "' + name + ' diagnostic" >&2\n'
                                   + 'exit ' + str(status) + '\n')
                program.chmod(0o755)
            env = dict(os.environ, PATH=directory, CALL_LOG=str(log))
            result = subprocess.run(['/bin/sh', str(ROOT / 'layout/DEBIAN' / script), action],
                                    env=env, capture_output=True, text=True)
            calls = log.read_text().splitlines() if log.exists() else []
            self.assertEqual(result.returncode, 0, result.stderr)
            return calls, result.stdout, result.stderr

    def test_success_is_not_claimed_as_verified(self):
        for script, action in [('postinst', 'configure'), ('postrm', 'remove')]:
            with self.subTest(script=script):
                calls, out, err = self.run_script(script, action)
                self.assertEqual(calls, ['launchctl kickstart -k system/com.apple.thermalmonitord'])
                self.assertIn('launchctl diagnostic', err)
                self.assertIn('not confirmed', out)
                self.assertIn('manually respring', out)

    def test_fallback_success_is_not_reload_confirmation(self):
        for script, action in [('postinst', 'configure'), ('postrm', 'remove')]:
            with self.subTest(script=script):
                calls, out, err = self.run_script(script, action, launch_status=42)
                self.assertEqual(calls, ['launchctl kickstart -k system/com.apple.thermalmonitord',
                                         'killall -TERM thermalmonitord'])
                self.assertIn('launchctl diagnostic', err)
                self.assertIn('exit 42', err)
                self.assertIn('killall diagnostic', err)
                self.assertIn('restart and reload are not confirmed', err)
                self.assertIn('manually respring', out)

    def test_both_commands_fail(self):
        for script, action in [('postinst', 'configure'), ('postrm', 'remove')]:
            calls, _, err = self.run_script(script, action, launch_status=42, kill_status=13)
            self.assertEqual(len(calls), 2)
            self.assertIn('exit 42', err)
            self.assertIn('exit 13', err)
            self.assertIn('daemon reload is not confirmed', err)

    def test_missing_commands(self):
        for script, action in [('postinst', 'configure'), ('postrm', 'remove')]:
            calls, _, err = self.run_script(script, action, launch_present=False)
            self.assertEqual(calls, ['killall -TERM thermalmonitord'])
            self.assertIn('launchctl unavailable', err)
            self.assertIn('not confirmed', err)
            calls, _, err = self.run_script(script, action, launch_present=False, kill_present=False)
            self.assertEqual(calls, [])
            self.assertIn('launchctl unavailable', err)
            self.assertIn('killall unavailable', err)
            self.assertIn('not confirmed', err)
            calls, _, err = self.run_script(script, action, launch_status=2, kill_present=False)
            self.assertEqual(len(calls), 1)
            self.assertIn('exit 2', err)
            self.assertIn('killall unavailable', err)

    def test_lifecycle_noops(self):
        for script, actions in {'prerm': ['remove', 'upgrade', 'deconfigure'],
                                'postinst': ['abort-upgrade', 'abort-remove', ''],
                                'postrm': ['purge', 'upgrade', 'failed-upgrade', 'abort-install']}.items():
            for action in actions:
                with self.subTest(script=script, action=action):
                    calls, out, err = self.run_script(script, action)
                    self.assertEqual((calls, out, err), ([], '', ''))


if __name__ == '__main__':
    unittest.main()
