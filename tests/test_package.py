import io
import gzip
from pathlib import Path
import subprocess
import sys
import tarfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from verify_package import decompress_tar, package_archives, tar_members

class PayloadValidation(unittest.TestCase):
    def archive(self, *items):
        out = io.BytesIO()
        with tarfile.open(fileobj=out, mode='w') as archive:
            for name, kind, mode in items:
                item = tarfile.TarInfo(name)
                item.uid, item.mode, item.type = 0, mode, kind
                if kind in (tarfile.SYMTYPE, tarfile.LNKTYPE): item.linkname = '/outside'
                archive.addfile(item, io.BytesIO(b''))
        return out.getvalue()

    def test_ar_size_field_matches_decimal_archive_syntax(self):
        import tempfile
        from verify_package import ar_members
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'size.deb'
            for field in (b'+4        ', b'0_4       ', b'\t4        ', b'4\t        ',
                          b'4\r        ', b'4\n        ', b'4\v        ', b'4\f        ',
                          b'-4        ', b'4 0       ', b'          '):
                header = f'{"debian-binary/":<16}{0:<12}{0:<6}{0:<6}{"100644":<8}'.encode() + field + b'`\n'
                path.write_bytes(b'!<arch>\n' + header + b'2.0\n')
                with self.subTest(field=field), self.assertRaisesRegex(AssertionError, 'size field'):
                    ar_members(path)

    def test_ar_member_names_are_not_trimmed_or_collapsed(self):
        import tempfile
        from verify_package import ar_members
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'name.deb'
            for name in (b'debian-binary//', b' debian-binary/', b'\tdebian-binary/',
                         b'debian-binary/\t', b'\xc2\xa0debian-binary', b'debian-binary\0'):
                header = name.ljust(16, b' ') + f'{0:<12}{0:<6}{0:<6}{"100644":<8}{4:<10}`\n'.encode()
                path.write_bytes(b'!<arch>\n' + header + b'2.0\n')
                with self.subTest(name=name), self.assertRaisesRegex(AssertionError, 'name field'):
                    ar_members(path)

    def test_ar_valid_names_and_decimal_padding(self):
        import tempfile
        from verify_package import ar_members
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'valid.deb'
            for name in (b'debian-binary', b'debian-binary/'):
                for size in (b'4         ', b'         4', b'0000000004'):
                    header = name.ljust(16, b' ') + f'{0:<12}{0:<6}{0:<6}{"100644":<8}'.encode() + size + b'`\n'
                    path.write_bytes(b'!<arch>\n' + header + b'2.0\n')
                    with self.subTest(name=name, size=size):
                        self.assertEqual(ar_members(path), {'debian-binary': b'2.0\n'})

    def test_normalization_rejects_invalid_ar_without_rewriting(self):
        import tempfile
        from normalize_package import normalize
        valid = (b'!<arch>\n' + f'{"debian-binary/":<16}{0:<12}{0:<6}{0:<6}{"100644":<8}{4:<10}`\n'.encode() + b'2.0\n')
        for start, field, reason in ((56, b'+4        ', 'size field'),
                                      (8, b'debian-binary// ', 'name field')):
            data = bytearray(valid); data[start:start + len(field)] = field
            with tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / 'bad.deb'; path.write_bytes(data)
                with self.assertRaisesRegex(AssertionError, reason):
                    normalize(path, 12345)
                self.assertEqual(path.read_bytes(), bytes(data))
                self.assertFalse(path.with_suffix('.deb.normalized').exists())

    def test_regular_file(self):
        self.assertIn('valid', tar_members(self.archive(('valid', tarfile.REGTYPE, 0o644))))

    def test_debian_member_order(self):
        import itertools
        members = {'debian-binary': b'2.0\n', 'control.tar.gz': gzip.compress(self.archive()),
                   'data.tar.gz': gzip.compress(self.archive())}
        package_archives(members)
        for order in itertools.permutations(members):
            if list(order) != list(members):
                with self.assertRaisesRegex(AssertionError, 'order'):
                    package_archives({name: members[name] for name in order})

    def test_compression_suffix_matches_bytes(self):
        import gzip
        import lzma
        raw = self.archive()
        for suffix, blob in [('gz', gzip.compress(raw)), ('xz', lzma.compress(raw)),
                             ('lzma', lzma.compress(raw, format=lzma.FORMAT_ALONE))]:
            members = {'debian-binary': b'2.0\n', 'control.tar.gz': gzip.compress(self.archive()), 'data.tar.' + suffix: blob}
            package_archives(members)
        members['data.tar.lzma'] = gzip.compress(raw)
        with self.assertRaisesRegex(AssertionError, 'compression'):
            package_archives(members)
        with self.assertRaisesRegex(AssertionError, 'suffix'):
            package_archives({'debian-binary': b'2.0\n', 'control.tar.bogus': self.archive(),
                              'data.tar.gz': gzip.compress(self.archive())})

    def test_nested_compression_is_not_a_tar_layer(self):
        import gzip
        import lzma
        raw = self.archive(('valid', tarfile.REGTYPE, 0o644))
        compressors = {'gz': gzip.compress, 'xz': lzma.compress,
                       'lzma': lambda b: lzma.compress(b, format=lzma.FORMAT_ALONE)}
        for outer, compress in compressors.items():
            for inner in (gzip.compress, lzma.compress):
                for role in ('control', 'data'):
                    members = {'debian-binary': b'2.0\n', 'control.tar.gz': gzip.compress(self.archive()),
                               'data.tar.gz': gzip.compress(self.archive())}
                    members = {(role + '.tar.' + outer if name.startswith(role + '.tar.') else name):
                               (compress(inner(raw)) if name.startswith(role + '.tar.') else blob)
                               for name, blob in members.items()}
                    with self.subTest(outer=outer, inner=inner.__module__, role=role):
                        with self.assertRaisesRegex(AssertionError, 'uncompressed tar'):
                            package_archives(members)

    def test_tar_end_markers_and_full_trailer_coverage(self):
        import gzip
        raw = self.archive(('valid', tarfile.REGTYPE, 0o644))
        # One header, empty payload, then at least two complete zero blocks.
        for valid in (raw, raw[:512] + bytes(1024), raw + bytes(512)):
            with self.subTest(valid_size=len(valid)):
                tar_members(valid)
        for invalid in (raw[:512], raw[:1024], raw[:-1], raw + b'UNREVIEWED',
                        raw + b'X' + bytes(511), raw + raw):
            with self.subTest(invalid_size=len(invalid)):
                with self.assertRaisesRegex(AssertionError, 'uncompressed tar'):
                    tar_members(invalid)

    def test_valid_tar_formats_and_payload_padding(self):
        for fmt in (tarfile.USTAR_FORMAT, tarfile.GNU_FORMAT, tarfile.PAX_FORMAT):
            for size in (1, 511, 512, 513):
                out = io.BytesIO(); payload = b'P' * size
                name = 'payload' if fmt == tarfile.USTAR_FORMAT else 'long/' * 40 + 'payload'
                with tarfile.open(fileobj=out, mode='w', format=fmt) as archive:
                    item = tarfile.TarInfo(name); item.size = size; item.mode = 0o644
                    archive.addfile(item, io.BytesIO(payload))
                with self.subTest(format=fmt, size=size):
                    self.assertEqual(tar_members(out.getvalue())[name][1], payload)

    def test_normalization_cannot_silently_repair_invalid_layers(self):
        import gzip
        import tempfile
        from normalize_package import normalize
        raw = self.archive(('valid', tarfile.REGTYPE, 0o644))
        for invalid in (gzip.compress(raw), raw + b'X' + bytes(511)):
            blob = gzip.compress(invalid)
            header = f'{"data.tar.gz/":<16}{0:<12}{0:<6}{0:<6}{"100644":<8}{len(blob):<10}`\n'.encode()
            original = b'!<arch>\n' + header + blob + (b'\n' if len(blob) & 1 else b'')
            # ar_members also requires a debian-binary member.
            binary = f'{"debian-binary/":<16}{0:<12}{0:<6}{0:<6}{"100644":<8}{4:<10}`\n'.encode() + b'2.0\n'
            original = original[:8] + binary + original[8:]
            with tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / 'negative.deb'
                path.write_bytes(original)
                with self.assertRaisesRegex(AssertionError, 'uncompressed tar'):
                    normalize(path, 12345)
                self.assertEqual(path.read_bytes(), original)
                self.assertFalse(path.with_suffix('.deb.normalized').exists())

    def test_directories_must_be_traversable(self):
        tar_members(self.archive(('.', tarfile.DIRTYPE, 0o755), ('Library', tarfile.DIRTYPE, 0o755)))
        for mode in (0, 0o644, 0o700, 0o777):
            with self.assertRaisesRegex(AssertionError, 'directory|permissions'):
                tar_members(self.archive(('Library', tarfile.DIRTYPE, mode)))

    def test_directory_allowlist_accepts_only_payload_ancestors(self):
        allowed = {'Library/Reviewed/file'}
        tar_members(self.archive(('.', tarfile.DIRTYPE, 0o755), ('Library', tarfile.DIRTYPE, 0o755),
                                 ('Library/Reviewed', tarfile.DIRTYPE, 0o755),
                                 ('Library/Reviewed/file', tarfile.REGTYPE, 0o644)), allowed)
        for name in ('unreviewed', 'Library/Other', 'Library/Reviewed/extra', 'Library/Reviewed/file'):
            with self.assertRaisesRegex(AssertionError, 'unexpected package directory'):
                tar_members(self.archive((name, tarfile.DIRTYPE, 0o755)), allowed)

    def test_control_archive_cannot_add_directories(self):
        with self.assertRaisesRegex(AssertionError, 'unexpected package directory'):
            tar_members(self.archive(('unexpected', tarfile.DIRTYPE, 0o755)), {'control', 'postinst'})

    def test_noncanonical_paths(self):
        for name in ('Library//x', 'Library/./x', '././Library/x', '', '/x', 'control/', 'Library/x/'):
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
        with tarfile.open(fileobj=out, mode='w') as archive:
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
            files = tar_members(decompress_tar('data.tar.gz', ar_members(path)['data.tar.gz']))
            self.assertEqual(files['payload'][1], payload)
            self.assertEqual(files['payload'][0].mtime, 12345)
            normalize(path, 12345)
            self.assertEqual(path.read_bytes(), normalized)
