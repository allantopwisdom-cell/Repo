"""A structurally valid package must still match the reviewed scripts and assets."""
from pathlib import Path
import plistlib
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from verify_package import control_fields, verify_source_contents


class SourcePackageValidation(unittest.TestCase):
    def fixtures(self):
        controls = {'control': (None, (ROOT / 'control').read_bytes())}
        for name in ('postinst', 'prerm', 'postrm'):
            controls[name] = (None, (ROOT / 'layout/DEBIAN' / name).read_bytes())
        files = {}
        for path in (ROOT / 'layout/Library').rglob('*'):
            if path.is_file(): files[str(path.relative_to(ROOT / 'layout'))] = (None, path.read_bytes())
        name = 'Library/MobileSubstrate/DynamicLibraries/PowercuffBaldaranTrusted.plist'
        files[name] = (None, plistlib.dumps(plistlib.loads((ROOT / 'PowercuffBaldaranTrusted.plist').read_bytes()), fmt=plistlib.FMT_BINARY))
        return controls, files

    def test_binary_plist_semantics_are_accepted(self):
        controls, files = self.fixtures()
        verify_source_contents(controls, files, ROOT)

    def test_unreviewed_maintainer_script_is_rejected(self):
        controls, files = self.fixtures()
        controls['postinst'] = (None, controls['postinst'][1] + b'\necho unreviewed\n')
        with self.assertRaisesRegex(AssertionError, 'postinst differs'):
            verify_source_contents(controls, files, ROOT)

    def test_changed_dependency_metadata_is_rejected(self):
        controls, files = self.fixtures()
        controls['control'] = (None, controls['control'][1].replace(b'preferenceloader', b'unreviewed-dependency'))
        with self.assertRaisesRegex(AssertionError, 'control metadata'):
            verify_source_contents(controls, files, ROOT)

    def test_changed_image_and_plist_are_rejected(self):
        for suffix in ('icon.png', 'Powercuff.plist'):
            controls, files = self.fixtures()
            name = next(name for name in files if name.endswith('/' + suffix))
            content = files[name][1]
            if suffix.endswith('.plist'):
                value = plistlib.loads(content); value['unexpected'] = True; content = plistlib.dumps(value)
            else:
                content = content[:-1] + bytes([content[-1] ^ 1])
            files[name] = (None, content)
            with self.assertRaisesRegex(AssertionError, 'differs'):
                verify_source_contents(controls, files, ROOT)

    def test_control_continuations_are_not_silently_ignored(self):
        self.assertEqual(control_fields(b'Description: first\n second\n')['Description'], 'first\nsecond')
        with self.assertRaisesRegex(AssertionError, 'continuation'):
            control_fields(b' unexpected continuation\n')
        with self.assertRaisesRegex(AssertionError, 'duplicate'):
            control_fields(b'Name: a\nName: b\n')
