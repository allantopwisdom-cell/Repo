import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class MaintainerScripts(unittest.TestCase):
    def run_script(self, script, action, launch_status=0):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            log = folder / 'calls'
            for name in ('launchctl', 'killall', 'defaults', 'notify_post'):
                program = folder / name
                program.write_text('#!/bin/sh\nprintf "%s\\n" "' + name + ' $*" >> "$CALL_LOG"\n' +
                                   ('exit "$LAUNCH_STATUS"\n' if name == 'launchctl' else 'exit 0\n'))
                program.chmod(0o755)
            env = dict(os.environ, PATH=directory, CALL_LOG=str(log), LAUNCH_STATUS=str(launch_status))
            subprocess.run(['/bin/sh', str(ROOT / 'layout/DEBIAN' / script), action],
                           env=env, check=True, capture_output=True)
            return log.read_text().splitlines() if log.exists() else []

    def test_success_never_double_restarts(self):
        for script, action in [('postinst', 'configure'), ('postrm', 'remove')]:
            self.assertEqual(self.run_script(script, action),
                             ['launchctl kickstart -k system/com.apple.thermalmonitord'])

    def test_failure_uses_one_term_fallback(self):
        for script, action in [('postinst', 'configure'), ('postrm', 'remove')]:
            self.assertEqual(self.run_script(script, action, 1),
                             ['launchctl kickstart -k system/com.apple.thermalmonitord',
                              'killall -TERM thermalmonitord'])

    def test_lifecycle_noops(self):
        for script, actions in {'prerm': ['remove', 'upgrade', 'deconfigure'],
                                'postinst': ['abort-upgrade', 'abort-remove', ''],
                                'postrm': ['purge', 'upgrade', 'failed-upgrade', 'abort-install']}.items():
            for action in actions:
                self.assertEqual(self.run_script(script, action), [])

if __name__ == '__main__':
    unittest.main()
