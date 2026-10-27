import io
from pathlib import Path
import subprocess
import sys
import tarfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from verify_package import package_archives, tar_members

class PayloadValidation(unittest.TestCase):
    def archive(self, *items):
        out = io.BytesIO()
        with tarfile.open(fileobj=out, mode='w:gz') as archive:
            for name, kind, mode in items:
                item = tarfile.TarInfo(name)
                item.uid, item.mode, item.type = 0, mode, kind
                if kind in (tarfile.SYMTYPE, tarfile.LNKTYPE): item.linkname = '/outside'
                archive.addfile(item, io.BytesIO(b''))
        return out.getvalue()

    def test_regular_file(self):
        self.assertIn('valid', tar_members(self.archive(('valid', tarfile.REGTYPE, 0o644))))

    def test_debian_member_order(self):
        import itertools
        members = {'debian-binary': b'2.0\n', 'control.tar.gz': self.archive(), 'data.tar.gz': self.archive()}
        package_archives(members)
        for order in itertools.permutations(members):
            if list(order) != list(members):
                with self.assertRaisesRegex(AssertionError, 'order'):
                    package_archives({name: members[name] for name in order})

    def test_compression_suffix_matches_bytes(self):
        import gzip
        import lzma
        raw = gzip.decompress(self.archive())
        for suffix, blob in [('gz', gzip.compress(raw)), ('xz', lzma.compress(raw)),
                             ('lzma', lzma.compress(raw, format=lzma.FORMAT_ALONE))]:
            members = {'debian-binary': b'2.0\n', 'control.tar.gz': self.archive(), 'data.tar.' + suffix: blob}
            package_archives(members)
        members['data.tar.lzma'] = gzip.compress(raw)
        with self.assertRaisesRegex(AssertionError, 'compression'):
            package_archives(members)
        with self.assertRaisesRegex(AssertionError, 'suffix'):
            package_archives({'debian-binary': b'2.0\n', 'control.tar.bogus': self.archive(), 'data.tar.gz': self.archive()})

    def test_directories_must_be_traversable(self):
        tar_members(self.archive(('.', tarfile.DIRTYPE, 0o755), ('Library', tarfile.DIRTYPE, 0o755)))
        for mode in (0, 0o644, 0o700, 0o777):
            with self.assertRaisesRegex(AssertionError, 'directory|permissions'):
                tar_members(self.archive(('Library', tarfile.DIRTYPE, mode)))

    def test_noncanonical_paths(self):
        for name in ('Library//x', 'Library/./x', '././Library/x', '', '/x'):
            with self.assertRaisesRegex(AssertionError, 'path'):
                tar_members(self.archive((name, tarfile.REGTYPE, 0o644)))

    def test_ar_negative_size_and_missing_padding(self):
        import tempfile
        from verify_package import ar_members
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'bad.deb'
            for size, content in ((-1, b''), (1, b'x')):
                header = f'{"x/":<16}{0:<12}{0:<6}{0:<6}{"100644":<8}{size:<10}`\n'.encode()
                path.write_bytes(b'!<arch>\n' + header + content)
                with self.assertRaises(AssertionError):
                    ar_members(path)

    def test_link_and_special_members(self):
        for kind in (tarfile.SYMTYPE, tarfile.LNKTYPE, tarfile.CHRTYPE, tarfile.FIFOTYPE):
            with self.assertRaises(AssertionError):
                tar_members(self.archive(('injected', kind, 0o644)))

    def test_unsafe_paths_permissions_and_duplicates(self):
        for name, mode in (('../escape', 0o644), ('/absolute', 0o644), ('x', 0o666), ('x', 0o4755)):
            with self.assertRaises(AssertionError):
                tar_members(self.archive((name, tarfile.REGTYPE, mode)))
        with self.assertRaises(AssertionError):
            tar_members(self.archive(('x', tarfile.REGTYPE, 0o644), ('./x', tarfile.REGTYPE, 0o644)))

    def test_optimized_python_refuses_validation(self):
        result = subprocess.run([sys.executable, '-O', '-c', 'import verify_package'],
                                cwd=Path(__file__).resolve().parents[1] / 'scripts', capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b'requires Python without -O', result.stderr)

    def test_numeric_uid_is_authoritative(self):
        out = io.BytesIO()
        with tarfile.open(fileobj=out, mode='w:gz') as archive:
            item = tarfile.TarInfo('looks-root')
            item.uid, item.gid, item.uname, item.gname, item.mode = 501, 20, 'root', 'wheel', 0o644
            archive.addfile(item)
        with self.assertRaises(AssertionError):
            tar_members(out.getvalue())

    def test_normalization_preserves_payload_and_is_repeatable(self):
        import tempfile
        from normalize_package import normalize
        from verify_package import ar_members
        payload = b'signed-payload-bytes'
        raw = io.BytesIO()
        with tarfile.open(fileobj=raw, mode='w:gz') as archive:
            item = tarfile.TarInfo('payload')
            item.uid, item.gid, item.mode, item.size = 501, 20, 0o644, len(payload)
            archive.addfile(item, io.BytesIO(payload))
        members = {'debian-binary': b'2.0\n', 'data.tar.gz': raw.getvalue()}
        data = bytearray(b'!<arch>\n')
        for name, blob in members.items():
            data.extend(f'{name + "/":<16}{0:<12}{501:<6}{20:<6}{"100644":<8}{len(blob):<10}`\n'.encode())
            data.extend(blob)
            if len(blob) & 1: data.extend(b'\n')
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'test.deb'
            path.write_bytes(data)
            normalize(path, 12345)
            normalized = path.read_bytes()
            files = tar_members(ar_members(path)['data.tar.gz'])
            self.assertEqual(files['payload'][1], payload)
            self.assertEqual(files['payload'][0].mtime, 12345)
            normalize(path, 12345)
            self.assertEqual(path.read_bytes(), normalized)
