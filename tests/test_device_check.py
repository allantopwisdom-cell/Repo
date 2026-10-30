"""Run the device collector with isolated command fixtures; never touch device services."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'Powercuff-1.3.4-device-check.sh'
PAYLOAD = dict((path, digest) for digest, path in re.findall(r'^([0-9a-f]{64}) (/Library/.*)$', SCRIPT.read_text(), re.M))
PREFIX = 0x5043020000000000

STUB = '''
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
c = json.loads(os.environ['PC_FIXTURE'])
with open(c['log'], 'a') as f: f.write(json.dumps([name, args]) + '\\n')
if name == 'id': print(c.get('uid', '501'))
elif name == 'date': print('2026-10-27T00:00:00Z')
elif name == 'sysctl':
 assert args[0] == '-n'
 print({'hw.machine': c.get('model', 'iPhone15,3'), 'kern.osproductversion': '16.5', 'kern.osversion': '20F66'}[args[1]])
elif name == 'dpkg-query':
 assert args[-1] == 'com.minis.powercuff-baldaran-trusted'
 if args[0] == '-L': print('\\n'.join(c['root'] + path for path in c['payload']))
 else:
  assert args[0] == '-W'
  print({'-f=${Status}': 'install ok installed', '-f=${Version}': c.get('version', '1.3.4'), '-f=${Architecture}': 'iphoneos-arm64e'}[args[1]])
elif name == 'jbroot':
 assert len(args) == 1 and args[0] in c['payload']
 print(c['root'] + args[0])
elif name in ('sha256sum', 'shasum', 'openssl'):
 path = args[-1]
 assert path.startswith(c['root'])
 digest = c['payload'][path[len(c['root']):]]
 if c.get('different_disk'): digest = '0' * 64
 print(('SHA256(x) = ' + digest) if name == 'openssl' else (digest + '  ' + path))
elif name == 'pgrep':
 assert args[0] == '-x' and args[1] in ('SpringBoard', 'thermalmonitord')
 if c.get('no_daemon') and args[1] == 'thermalmonitord': sys.exit(1)
 print('101' if args[1] == 'SpringBoard' else '102')
elif name == 'ps':
 assert args[0] == '-p' and args[2:] == ['-o', 'pid=,etime=,comm=']
 print(args[1], '00:10', 'test-process')
elif name == 'defaults':
 assert args[:2] == ['read', 'com.minis.powercuff-baldaran-trusted']
 assert args[2] in ('PowerMode', 'RequireLowPowerMode')
 if c.get('missing_prefs'): sys.exit(1)
 print(c.get('mode', 2) if args[2] == 'PowerMode' else 0)
elif name == 'notifyutil':
 assert args[0] == '-g' and len(args) == 2
 key = args[1]
 suffix = key.removeprefix('com.minis.powercuff-baldaran-trusted.')
 if c.get('notify_error'):
  print(key + ': Failed with code 1'); sys.exit(0)
 session = 23
 values = {'loaded.s': 1, 'loaded.t': 1, 'hook': 1,
  'request': c['prefix'] | (session << 8) | 165,
  'thermals': c['prefix'] | ((session + int(c.get('stale_session', False))) << 8) | c.get('mode', 2),
  'applied': c.get('applied', c.get('mode', 2))}
 print(key, values[suffix])
else:
 raise AssertionError('Unexpected command: ' + name)
'''


class DeviceCheck(unittest.TestCase):
    def run_collector(self, *args, **options):
        with tempfile.TemporaryDirectory(prefix='powercuff-check-') as directory:
            root = Path(directory)
            bin_dir = root / 'bin'
            bin_dir.mkdir()
            payload_root = root / 'root with spaces'
            for name in PAYLOAD:
                path = payload_root / name.lstrip('/')
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b'test fixture; hashing command is mocked')
            config = dict(root=str(payload_root), log=str(root / 'calls.jsonl'), payload=PAYLOAD, prefix=PREFIX, **options)
            commands = ['id', 'date', 'sysctl', 'dpkg-query', 'pgrep', 'ps', 'defaults', 'notifyutil', options.get('hash_tool', 'sha256sum')]
            if not options.get('no_jbroot'): commands.append('jbroot')
            for name in commands:
                path = bin_dir / name
                path.write_text('#!' + sys.executable + '\n' + STUB)
                path.chmod(0o755)
            (bin_dir / 'awk').symlink_to(shutil.which('awk'))
            env = dict(os.environ, PATH=str(bin_dir), PC_FIXTURE=json.dumps(config))
            result = subprocess.run(['/bin/sh', str(SCRIPT), *args], env=env, capture_output=True, text=True, timeout=20)
            log = Path(config['log'])
            calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
            return result, calls

    def test_shell_syntax_and_help(self):
        subprocess.run(['/bin/sh', '-n', str(SCRIPT)], check=True)
        result, calls = self.run_collector('--help')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(calls, [])

    def test_matching_snapshot_uses_only_read_commands(self):
        result, calls = self.run_collector('--label', 'light')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout.count('DISK-MATCH:'), 6)
        self.assertIn('SESSION-MATCH: session=23, published mode=2', result.stdout)
        self.assertIn('NOT-RELEASE-APPROVAL', result.stdout)
        for name, args in calls:
            if name == 'defaults': self.assertEqual(args[0], 'read')
            if name == 'notifyutil': self.assertEqual(args[0], '-g')
            if name == 'sysctl': self.assertEqual(args[0], '-n')

    def test_root_is_refused_before_collection(self):
        result, calls = self.run_collector(uid='0')
        self.assertEqual(result.returncode, 2)
        self.assertEqual(calls, [['id', ['-u']]])

    def test_unexpected_stage_is_not_executed(self):
        result, calls = self.run_collector('--label', '$(touch injected)')
        self.assertEqual(result.returncode, 2)
        self.assertEqual(calls, [])

    def test_notify_error_with_success_exit_is_not_pass(self):
        result, _ = self.run_collector(notify_error=True)
        self.assertEqual(result.returncode, 3)
        self.assertIn('Unrecognized or failed notification read', result.stdout)
        self.assertNotIn('SESSION-MATCH:', result.stdout)

    def test_old_session_is_unverified(self):
        result, _ = self.run_collector(stale_session=True)
        self.assertEqual(result.returncode, 3)
        self.assertNotIn('SESSION-MATCH:', result.stdout)

    def test_timeout_and_abi_diagnostics_block_acceptance(self):
        for status in (11, 98, 99):
            result, _ = self.run_collector(applied=status)
            self.assertEqual(result.returncode, 1)

    def test_missing_process_wrong_package_or_wrong_stage(self):
        for args, options in [((), {'no_daemon': True}), ((), {'version': '1.3.2'}),
                              (('--label', 'off-after'), {}), ((), {'model': 'other'})]:
            result, _ = self.run_collector(*args, **options)
            self.assertEqual(result.returncode, 1)

    def test_disk_difference_is_not_called_corruption(self):
        result, _ = self.run_collector(different_disk=True)
        self.assertEqual(result.returncode, 3)
        self.assertIn('installer patching/resigning may change bytes', result.stdout)

    def test_dpkg_paths_and_other_hash_tools(self):
        for hash_tool in ('shasum', 'openssl'):
            result, _ = self.run_collector(no_jbroot=True, hash_tool=hash_tool)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(result.stdout.count('DISK-MATCH:'), 6)

    def test_missing_preferences_remain_unknown(self):
        result, _ = self.run_collector(missing_prefs=True)
        self.assertEqual(result.returncode, 3)
        self.assertIn('a missing key alone is not a plugin fault', result.stdout)
