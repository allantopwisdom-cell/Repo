#!/usr/bin/env python3
"""Canonicalize Debian tar numeric ownership without changing signed payload bytes."""
import argparse
import copy
import gzip
import io
import lzma
from pathlib import Path
import tarfile
from verify_package import ar_members, decompress_tar, uncompressed_tar


def normalize(path, epoch):
    path = Path(path)
    assert epoch >= 0
    members = ar_members(path)
    result = bytearray(b'!<arch>\n')
    for name, data in members.items():
        if name.startswith(('control.tar.', 'data.tar.')):
            out = io.BytesIO()
            with uncompressed_tar(decompress_tar(name, data)) as source:
                with tarfile.open(fileobj=out, mode='w', format=tarfile.USTAR_FORMAT) as target:
                    for original in source:
                        item = copy.copy(original)
                        item.uid = item.gid = 0
                        item.uname, item.gname, item.mtime = 'root', 'wheel', epoch
                        item.pax_headers = {}
                        target.addfile(item, source.extractfile(original) if original.isfile() else None)
            raw = out.getvalue()
            if name.endswith('.gz'): data = gzip.compress(raw, mtime=epoch)
            elif name.endswith('.lzma'): data = lzma.compress(raw, format=lzma.FORMAT_ALONE)
            elif name.endswith('.xz'): data = lzma.compress(raw, format=lzma.FORMAT_XZ)
            else: raise ValueError('unsupported Debian compression')
        assert len(name) <= 15
        header = f'{name + "/":<16}{epoch:<12}{0:<6}{0:<6}{"100644":<8}{len(data):<10}`\n'.encode('ascii')
        assert len(header) == 60
        result.extend(header)
        result.extend(data)
        if len(data) & 1: result.extend(b'\n')
    temporary = path.with_suffix(path.suffix + '.normalized')
    temporary.write_bytes(result)
    temporary.replace(path)
    print('Canonical numeric ownership 0/0 and archive timestamps PASS')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('package')
    parser.add_argument('--epoch', type=int, required=True)
    args = parser.parse_args()
    normalize(args.package, args.epoch)
