"""Exercise the current read-only helper with isolated commands, never a device."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
STUB = '''import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['CALL_LOG'], 'a') as log: log.write(json.dumps([name, args]) + '\\n')
if name == 'id':
 print(os.environ.get('TEST_UID', '501')); sys.exit(int(os.environ.get('ID_STATUS', '0')))
elif name == 'defaults':
 assert args == ['read', 'com.minis.powercuff-baldaran-trusted']; print('{ PowerMode = 0; }'); sys.exit(int(os.environ.get('DEFAULTS_STATUS', '0')))
elif name == 'notifyutil':
 assert args[0] == '-g'; print(args[1], '0')
elif name == 'dpkg-query':
 assert args[0] == '-W'; print('Installed package: 1.3.11 iphoneos-arm64e')
else: raise AssertionError('unexpected command')
'''


class CurrentDiagnostics(unittest.TestCase):
    def run_helper(self, *args, uid='501', id_status='0', defaults_status='0'):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ('id', 'defaults', 'notifyutil', 'dpkg-query'):
                path = root / name
                path.write_text('#!' + sys.executable + '\n' + STUB); path.chmod(0o755)
            (root / 'cat').symlink_to(shutil.which('cat'))
            log = root / 'calls'
            env = dict(os.environ, PATH=directory, TEST_UID=uid, ID_STATUS=id_status, DEFAULTS_STATUS=defaults_status, CALL_LOG=str(log))
            result = subprocess.run(['/bin/sh', str(ROOT / 'verify-on-device.sh'), *args], env=env,
                                    capture_output=True, text=True, timeout=10)
            calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
            return result, calls

    def test_root_and_other_users_stop_before_any_collection(self):
        for uid in ('0', '502', 'invalid'):
            result, calls = self.run_helper(uid=uid)
            self.assertEqual(result.returncode, 2)
            self.assertEqual(calls, [['id', ['-u']]])

    def test_failed_identity_stops_before_any_collection(self):
        result, calls = self.run_helper(id_status='1')
        self.assertEqual(result.returncode, 2)
        self.assertEqual(calls, [['id', ['-u']]])

    def test_help_and_invalid_options_collect_nothing(self):
        for option, code in (('--help', 0), ('-h', 0), ('--unknown', 2)):
            result, calls = self.run_helper(option)
            self.assertEqual(result.returncode, code)
            self.assertEqual(calls, [])

    def test_mobile_collects_only_reads_and_includes_request(self):
        result, calls = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('not proof of liveness', result.stdout)
        self.assertIn('Installed package: 1.3.11', result.stdout)
        self.assertIn('--- request ---', result.stdout)
        self.assertIn('State 11 does not mean', result.stdout)
        for name, args in calls:
            self.assertIn(name, ('id', 'defaults', 'notifyutil', 'dpkg-query'))
            self.assertEqual(args[0], {'id': '-u', 'defaults': 'read', 'notifyutil': '-g', 'dpkg-query': '-W'}[name])


    def test_unreadable_preferences_do_not_claim_an_effective_off_mode(self):
        result, _ = self.run_helper(defaults_status='1')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('effective mode is unknown', result.stdout)
        self.assertIn('State 11 does not mean', result.stdout)


if __name__ == '__main__':
    unittest.main()
