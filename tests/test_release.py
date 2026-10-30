"""Publication must withhold incomplete or mismatched build attachments."""
import contextlib
import copy
import hashlib
import io
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from verify_release import verify_release


class ReleaseValidation(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.commit = 'a' * 40
        for name, data in {'SOURCE_COMMIT': (self.commit + '\n').encode(), 'VERSION': b'1.3.9\n',
                           'test.deb': b'fixture bytes, never installed'}.items():
            (self.root / name).write_bytes(data)
        manifest = ''.join(hashlib.sha256(p.read_bytes()).hexdigest() + '  ./' + p.name + '\n'
                           for p in sorted(self.root.iterdir()))
        (self.root / 'SHA256SUMS').write_text(manifest)
        self.release = dict(tag_name='v1.3.9', target_commitish=self.commit, draft=True, prerelease=False,
                            assets=[dict(name=p.name, state='uploaded', size=p.stat().st_size,
                                         digest='sha256:' + hashlib.sha256(p.read_bytes()).hexdigest())
                                    for p in self.root.iterdir()])

    def verify(self, release=None, draft=True, prerelease=False):
        with contextlib.redirect_stdout(io.StringIO()):
            verify_release(self.root, self.release if release is None else release, self.commit, 'v1.3.9', draft,
                           prerelease=prerelease)

    def test_complete_draft_and_public_release(self):
        self.verify()
        self.release['draft'] = False
        self.verify(draft=False)

    def test_missing_extra_duplicate_and_incomplete_assets(self):
        for mutation in ('missing', 'extra', 'duplicate', 'incomplete'):
            release = copy.deepcopy(self.release)
            if mutation == 'missing': release['assets'].pop()
            elif mutation == 'extra': release['assets'].append(dict(name='unreviewed'))
            elif mutation == 'duplicate': release['assets'].append(release['assets'][0])
            else: release['assets'][0]['state'] = 'new'
            with self.subTest(mutation=mutation), self.assertRaisesRegex(AssertionError, 'attachment'):
                self.verify(release)

    def test_wrong_source_visibility_size_or_digest(self):
        for mutation in ('commit', 'tag', 'draft', 'prerelease', 'size', 'digest'):
            release = copy.deepcopy(self.release)
            if mutation == 'commit': release['target_commitish'] = 'b' * 40
            elif mutation == 'tag': release['tag_name'] = 'v1.3.6'
            elif mutation in ('draft', 'prerelease'): release[mutation] = not release[mutation]
            elif mutation == 'size': release['assets'][0]['size'] += 1
            else: release['assets'][0]['digest'] = 'sha256:' + '0' * 64
            with self.subTest(mutation=mutation), self.assertRaises(AssertionError): self.verify(release)

    def test_manifest_must_cover_every_other_file_once(self):
        path = self.root / 'SHA256SUMS'
        original = path.read_text()
        for value in ('', original.splitlines()[0] + '\n', original + original.splitlines()[0] + '\n'):
            path.write_text(value)
            with self.assertRaisesRegex(AssertionError, 'manifest'): self.verify()
        path.write_text(original)
        (self.root / 'extra-file').write_text('unreviewed')
        with self.assertRaisesRegex(AssertionError, 'manifest coverage'): self.verify()

    def test_local_tampering_cannot_be_hidden_by_remote_metadata(self):
        (self.root / 'test.deb').write_bytes(b'changed after build')
        with self.assertRaisesRegex(AssertionError, 'local attachment hash'): self.verify()


    def test_release_type_is_explicit_and_cannot_be_mislabelled(self):
        self.release['prerelease'] = True
        with self.assertRaisesRegex(AssertionError, 'visibility/type'): self.verify()
        self.verify(prerelease=True)
        self.release['draft'] = False
        self.verify(draft=False, prerelease=True)
        self.release['prerelease'] = False
        with self.assertRaisesRegex(AssertionError, 'visibility/type'):
            self.verify(draft=False, prerelease=True)
        self.verify(draft=False)

    def test_cli_requires_an_explicit_release_type(self):
        metadata = self.root.parent / (self.root.name + '-metadata.json')
        self.addCleanup(metadata.unlink, missing_ok=True)
        metadata.write_text('{}')
        result = subprocess.run([sys.executable, str(Path(__file__).resolve().parents[1] / 'scripts/verify_release.py'),
                                 str(self.root), str(metadata), '--commit', self.commit, '--tag', 'v1.3.9', '--draft'],
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 2)
        self.assertIn('--prerelease --stable', result.stderr)


if __name__ == '__main__':
    unittest.main()
