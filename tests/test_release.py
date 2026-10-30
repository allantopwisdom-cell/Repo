"""Publication must withhold incomplete or mismatched build attachments."""
import contextlib
import copy
import hashlib
import io
from pathlib import Path
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
        for name, data in {'SOURCE_COMMIT': (self.commit + '\n').encode(), 'VERSION': b'1.3.7\n',
                           'test.deb': b'fixture bytes, never installed'}.items():
            (self.root / name).write_bytes(data)
        manifest = ''.join(hashlib.sha256(p.read_bytes()).hexdigest() + '  ./' + p.name + '\n'
                           for p in sorted(self.root.iterdir()))
        (self.root / 'SHA256SUMS').write_text(manifest)
        self.release = dict(tag_name='v1.3.7', target_commitish=self.commit, draft=True, prerelease=True,
                            assets=[dict(name=p.name, state='uploaded', size=p.stat().st_size,
                                         digest='sha256:' + hashlib.sha256(p.read_bytes()).hexdigest())
                                    for p in self.root.iterdir()])

    def verify(self, release=None, draft=True):
        with contextlib.redirect_stdout(io.StringIO()):
            verify_release(self.root, self.release if release is None else release, self.commit, 'v1.3.7', draft)

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
            elif mutation in ('draft', 'prerelease'): release[mutation] = False
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


if __name__ == '__main__':
    unittest.main()
