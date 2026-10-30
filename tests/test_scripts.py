import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
LABEL = 'com.apple.thermalmonitord'
FG = 'user/foreground/' + LABEL
SYSTEM = 'system/' + LABEL


class MaintainerScripts(unittest.TestCase):
    def run_script(self, script, action, launch_status=0, kill_status=0,
                   foreground_status=0, system_status=1,
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
                body = '#!/bin/sh\nprintf "%s\\n" "' + name + ' $*" >> "$CALL_LOG"\n'
                if name == 'launchctl':
                    body += ('if [ "$1" = print ]; then\n'
                             ' echo "probe diagnostic" >&2\n'
                             ' case "$2" in\n'
                             '  ' + FG + ') exit ' + str(foreground_status) + ';;\n'
                             '  ' + SYSTEM + ') exit ' + str(system_status) + ';;\n'
                             '  *) exit 99;;\n esac\nfi\n')
                    # Emulate the actual legacy-name warning without turning it
                    # into a failing command or hiding it from the script.
                    if foreground_status == 0:
                        body += ('if [ "$1" = kickstart ] && [ "$3" = "' + SYSTEM + '" ]; then\n'
                                 ' echo "Warning: Please switch to ' + FG + ' service identifier" >&2\nfi\n')
                    body += 'if [ "$1" = kill ]; then\n echo "targeted TERM diagnostic" >&2\n exit ' + str(kill_status) + '\nfi\n'
                    status = launch_status
                else:
                    status = kill_status if name == 'killall' else 0
                body += 'echo "' + name + ' diagnostic" >&2\nexit ' + str(status) + '\n'
                program.write_text(body)
                program.chmod(0o755)
            env = dict(os.environ, PATH=directory, CALL_LOG=str(log))
            result = subprocess.run(['/bin/sh', str(ROOT / 'layout/DEBIAN' / script), action],
                                    env=env, capture_output=True, text=True, timeout=10)
            calls = log.read_text().splitlines() if log.exists() else []
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertLessEqual(sum(call.startswith('launchctl kickstart ') for call in calls), 1)
            self.assertLessEqual(sum(call.startswith('launchctl kill SIGTERM ') for call in calls), 1)
            self.assertTrue(all(call.startswith(('launchctl print ', 'launchctl kickstart ',
                                                 'launchctl kill SIGTERM ')) for call in calls))
            return calls, result.stdout, result.stderr

    def test_prefers_foreground_without_legacy_warning(self):
        for script, action in [('postinst', 'configure'), ('postrm', 'remove')]:
            calls, out, err = self.run_script(script, action, system_status=0)
            self.assertEqual(calls, ['launchctl print ' + FG, 'launchctl kickstart -k ' + FG])
            self.assertIn(FG, out)
            self.assertIn('launchctl diagnostic', err)
            self.assertNotIn('Warning: Please switch', err)
            self.assertIn('not confirmed', out)
            self.assertIn('manually respring', out)

    def test_system_service_when_foreground_is_unavailable(self):
        for script, action in [('postinst', 'configure'), ('postrm', 'remove')]:
            calls, out, err = self.run_script(script, action, foreground_status=95, system_status=0)
            self.assertEqual(calls, ['launchctl print ' + FG, 'launchctl print ' + SYSTEM,
                                     'launchctl kickstart -k ' + SYSTEM])
            self.assertIn(SYSTEM, out)
            self.assertIn('launchctl diagnostic', err)
            self.assertNotIn('probe diagnostic', err)
            self.assertIn('not confirmed', out)

    def test_unresolved_domain_does_not_signal_any_process(self):
        for script, action in [('postinst', 'configure'), ('postrm', 'remove')]:
            calls, out, err = self.run_script(script, action, foreground_status=1, system_status=1)
            self.assertEqual(calls, ['launchctl print ' + FG, 'launchctl print ' + SYSTEM])
            self.assertIn('automatic restart skipped', err)
            self.assertIn('jailbreak app', err)
            self.assertIn('manually respring', out)

    def test_missing_launchctl_does_not_blindly_signal(self):
        for script, action in [('postinst', 'configure'), ('postrm', 'remove')]:
            calls, out, err = self.run_script(script, action, launch_present=False)
            self.assertEqual(calls, [])
            self.assertIn('launchctl unavailable', err)
            self.assertIn('automatic restart skipped', err)
            self.assertIn('manually respring', out)

    def test_foreground_kickstart_failure_has_one_term_fallback(self):
        for script, action in [('postinst', 'configure'), ('postrm', 'remove')]:
            calls, out, err = self.run_script(script, action, launch_status=42)
            self.assertEqual(calls, ['launchctl print ' + FG, 'launchctl kickstart -k ' + FG,
                                     'launchctl kill SIGTERM ' + FG])
            self.assertIn('launchctl diagnostic', err)
            self.assertIn('exit 42', err)
            self.assertIn('targeted TERM diagnostic', err)
            self.assertIn('restart and reload are not confirmed', err)
            self.assertIn('manually respring', out)

    def test_system_kickstart_failure_has_one_term_fallback(self):
        for script, action in [('postinst', 'configure'), ('postrm', 'remove')]:
            calls, _, err = self.run_script(script, action, foreground_status=1, system_status=0,
                                           launch_status=42)
            self.assertEqual(calls, ['launchctl print ' + FG, 'launchctl print ' + SYSTEM,
                                     'launchctl kickstart -k ' + SYSTEM, 'launchctl kill SIGTERM ' + SYSTEM])
            self.assertIn('exit 42', err)

    def test_kickstart_and_term_both_fail(self):
        for script, action in [('postinst', 'configure'), ('postrm', 'remove')]:
            calls, _, err = self.run_script(script, action, launch_status=42, kill_status=13)
            self.assertEqual(len(calls), 3)
            self.assertIn('exit 42', err)
            self.assertIn('exit 13', err)
            self.assertIn('daemon reload is not confirmed', err)

    def test_unsupported_targeted_signal_does_not_broaden_to_other_domains(self):
        for script, action in [('postinst', 'configure'), ('postrm', 'remove')]:
            calls, _, err = self.run_script(script, action, launch_status=42, kill_status=64, system_status=0)
            self.assertEqual(calls, ['launchctl print ' + FG, 'launchctl kickstart -k ' + FG,
                                     'launchctl kill SIGTERM ' + FG])
            self.assertIn('exit 42', err)
            self.assertIn('exit 64', err)
            self.assertIn('daemon reload is not confirmed', err)

    def test_success_never_falls_back_to_term(self):
        for script, action in [('postinst', 'configure'), ('postrm', 'remove')]:
            calls, out, _ = self.run_script(script, action, kill_status=13)
            self.assertEqual(calls, ['launchctl print ' + FG, 'launchctl kickstart -k ' + FG])
            self.assertIn('not confirmed', out)

    def test_lifecycle_noops(self):
        for script, actions in {'prerm': ['remove', 'upgrade', 'deconfigure'],
                                'postinst': ['abort-upgrade', 'abort-remove', ''],
                                'postrm': ['purge', 'upgrade', 'failed-upgrade', 'abort-install']}.items():
            for action in actions:
                calls, out, err = self.run_script(script, action)
                self.assertEqual((calls, out, err), ([], '', ''))


if __name__ == '__main__':
    unittest.main()
