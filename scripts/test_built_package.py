#!/usr/bin/env python3
"""Negative tests against the actual signed Mach-O from this build."""
import struct
import sys
from verify_package import ar_members, decompress_tar, tar_members
from macho_signature import verify_signature

members = ar_members(sys.argv[1])
name, = [n for n in members if n.startswith('data.tar.')]
files = tar_members(decompress_tar(name, members[name]))
name, = [n for n in files if n.endswith('.dylib')]
binary = files[name][1]
offset = 32
for _ in range(struct.unpack_from('<I', binary, 16)[0]):
    command, length = struct.unpack_from('<2I', binary, offset)
    if command == 0x1D:
        start, size = struct.unpack_from('<2I', binary, offset + 8)
        break
    offset += length
else:
    raise AssertionError('no signature')
verify_signature(binary, start, size)
for location in (0, start - 1, start):
    corrupt = bytearray(binary)
    corrupt[location] ^= 1
    try:
        verify_signature(corrupt, start, size)
    except AssertionError:
        pass
    else:
        raise AssertionError(f'corruption at {location} was not rejected')
try:
    verify_signature(binary[:-1], start, size)
except AssertionError:
    pass
else:
    raise AssertionError('truncated signature was not rejected')
print('Actual built Mach-O: tampered code, bad signature magic and truncation rejected PASS')

signature = binary[start:start + size]
for i in range(struct.unpack_from('>I', signature, 8)[0]):
    slot, relative = struct.unpack_from('>II', signature, 12 + i * 8)
    if slot == 2:
        corrupt = bytearray(binary)
        corrupt[start + relative + 8] ^= 1
        try:
            verify_signature(corrupt, start, size)
        except AssertionError:
            pass
        else:
            raise AssertionError('modified requirements special slot was not rejected')
        print('Actual built Mach-O: tampered requirements special-slot payload rejected PASS')
        break
else:
    raise AssertionError('expected requirements slot is absent')

# CodeDirectory metadata must not be able to shrink coverage to zero pages.
corrupt = bytearray(binary)
for i in range(struct.unpack_from('>I', signature, 8)[0]):
    slot, relative = struct.unpack_from('>II', signature, 12 + i * 8)
    if slot == 0 or 0x1000 <= slot < 0x1005:
        struct.pack_into('>II', corrupt, start + relative + 28, 0, 0)
try:
    verify_signature(corrupt, start, size)
except AssertionError:
    pass
else:
    raise AssertionError('zero-page signature coverage was not rejected')
print('Actual built Mach-O: zero-page signature coverage rejected PASS')

# Changing CodeDirectory metadata must not bypass coverage or change interpretation.
for label, relative, width, value in (
        ('missing-special-coverage', 24, 'I', 0),
        ('scatter-layout', 44, 'I', 1),
        ('extended-limit', 56, 'Q', start + 1),
        ('unknown-version', 8, 'I', 0xFFFFFF)):
    corrupt = bytearray(binary)
    for i in range(struct.unpack_from('>I', signature, 8)[0]):
        slot, directory = struct.unpack_from('>II', signature, 12 + i * 8)
        if slot == 0 or 0x1000 <= slot < 0x1005:
            struct.pack_into('>' + width, corrupt, start + directory + relative, value)
    try:
        verify_signature(corrupt, start, size)
    except AssertionError:
        pass
    else:
        raise AssertionError(f'signature metadata mutation {label} was accepted')
    print(f'Actual built Mach-O: {label} rejected PASS')

# Verify the complete DEB against this checkout, then mutate independently of Mach-O.
import contextlib
import copy
import io
import gzip
import lzma
from pathlib import Path
import plistlib
import tarfile
import tempfile
from verify_package import control_fields, verify

source_root = Path(__file__).resolve().parents[1]
control_name, = [n for n in members if n.startswith('control.tar.')]
data_name, = [n for n in members if n.startswith('data.tar.')]
version = control_fields(tar_members(decompress_tar(control_name, members[control_name]))['control'][1])['Version']
with contextlib.redirect_stdout(io.StringIO()):
    verify(sys.argv[1], version, source_root)

def compress_tar(raw, archive_name):
    if archive_name.endswith('.gz'): return gzip.compress(raw, mtime=0)
    return lzma.compress(raw, format=lzma.FORMAT_XZ if archive_name.endswith('.xz') else lzma.FORMAT_ALONE)

def mutate_tar(blob, scenario, archive_name):
    out = io.BytesIO()
    changed = False
    with tarfile.open(fileobj=io.BytesIO(blob)) as archive, tarfile.open(fileobj=out, mode='w') as target:
        for original in archive:
            item = copy.copy(original)
            payload = archive.extractfile(original).read() if original.isfile() else None
            if scenario == 'unreviewed-script' and item.name.removeprefix('./') == 'postinst':
                payload += b'\necho unreviewed\n'; changed = True
            elif scenario == 'changed-icon' and item.name.endswith('/icon.png'):
                payload = payload[:-1] + bytes([payload[-1] ^ 1]); changed = True
            elif scenario == 'unreadable-dylib' and item.name.endswith('.dylib'):
                item.mode = 0; changed = True
            elif scenario == 'legacy-arm64e-abi' and item.name.endswith('.dylib'):
                payload = bytearray(payload)
                struct.pack_into('<I', payload, 8, 2)
                payload = bytes(payload); changed = True
            elif scenario == 'trailing-file-slash' and item.name.removeprefix('./') == 'postinst':
                item.name += '/'; changed = True
            elif scenario in ('unreviewed-dependency', 'missing-dependency', 'duplicate-dependency',
                              'missing-conflict', 'split-control-stanza') and item.name.removeprefix('./') == 'control':
                if scenario == 'unreviewed-dependency':
                    payload = payload.replace(b'preferenceloader', b'unreviewed-dependency')
                elif scenario == 'missing-dependency':
                    payload = payload.replace(b'preferenceloader, ', b'')
                elif scenario == 'duplicate-dependency':
                    payload = payload.replace(b'preferenceloader', b'preferenceloader, preferenceloader')
                elif scenario == 'missing-conflict':
                    payload = payload.replace(b'com.rpetrich.powercuff, ', b'')
                else:
                    payload = payload.replace(b'Depends:', b'\nDepends:')
                changed = True
            elif scenario in ('boolean-profile', 'duplicate-plist-key') and item.name.endswith('/Powercuff.plist'):
                panel = plistlib.loads(payload)
                if scenario == 'boolean-profile':
                    next(i for i in panel['items'] if i.get('key') == 'PowerMode')['validValues'][1] = True
                    payload = plistlib.dumps(panel, fmt=plistlib.FMT_BINARY)
                else:
                    payload = plistlib.dumps(panel, fmt=plistlib.FMT_XML).replace(
                        b'<dict>', b'<dict><key>entry</key><dict/>', 1)
                changed = True
            if payload is not None: item.size = len(payload)
            target.addfile(item, io.BytesIO(payload) if payload is not None else None)
        if scenario in ('extra-control-directory', 'extra-data-directory'):
            extra = tarfile.TarInfo('unreviewed-empty-directory')
            extra.type, extra.mode, extra.uid, extra.gid = tarfile.DIRTYPE, 0o755, 0, 0
            target.addfile(extra); changed = True
    assert changed
    raw = out.getvalue()
    return compress_tar(raw, archive_name)

with tempfile.TemporaryDirectory() as directory:
    for scenario in ('unreviewed-script', 'changed-icon', 'unreadable-dylib', 'legacy-arm64e-abi', 'unreviewed-dependency',
                     'reordered-members', 'compression-name-mismatch', 'extra-control-directory', 'extra-data-directory',
                     'trailing-file-slash', 'boolean-profile', 'duplicate-plist-key', 'missing-dependency',
                     'duplicate-dependency', 'missing-conflict', 'split-control-stanza',
                     'nested-control-gzip', 'nested-control-xz', 'nested-data-gzip', 'nested-data-xz',
                     'tar-trailer-control', 'tar-trailer-data', 'tar-eof-control', 'tar-eof-data'):
        damaged = dict(members)
        if scenario == 'reordered-members':
            damaged = dict(reversed(list(damaged.items())))
        elif scenario == 'compression-name-mismatch':
            # Change only the label; preserve original compressed bytes.
            wrong_name = 'control.tar.xz' if control_name.endswith('.gz') else 'control.tar.gz'
            damaged = {(wrong_name if name == control_name else name): blob for name, blob in damaged.items()}
        elif scenario.startswith(('nested-', 'tar-trailer-', 'tar-eof-')):
            name = control_name if 'control' in scenario else data_name
            raw = decompress_tar(name, damaged[name])
            if scenario.startswith('nested-'):
                raw = gzip.compress(raw, mtime=0) if scenario.endswith('-gzip') else lzma.compress(raw)
            elif scenario.startswith('tar-trailer-'):
                raw += b'UNREVIEWED' + bytes(502) # Keep block alignment; content after EOF is still forbidden.
            else:
                with tarfile.open(fileobj=io.BytesIO(raw), mode='r:') as archive:
                    archive.getmembers()
                    raw = raw[:archive.offset] # No two-block tar end marker.
            damaged[name] = compress_tar(raw, name)
        else:
            name = control_name if scenario in ('unreviewed-script', 'unreviewed-dependency', 'extra-control-directory',
                                                'trailing-file-slash', 'missing-dependency', 'duplicate-dependency',
                                                'missing-conflict', 'split-control-stanza') else data_name
            damaged[name] = mutate_tar(damaged[name], scenario, name)
        data = bytearray(b'!<arch>\n')
        for name, payload in damaged.items():
            data.extend(f'{name + "/":<16}{0:<12}{0:<6}{0:<6}{"100644":<8}{len(payload):<10}`\n'.encode())
            data.extend(payload)
            if len(payload) & 1: data.extend(b'\n')
        path = Path(directory) / 'negative.deb'
        path.write_bytes(data)
        try:
            with contextlib.redirect_stdout(io.StringIO()): verify(path, version, source_root)
        except AssertionError as error:
            expected_reason = {'unreviewed-script': 'postinst differs', 'changed-icon': 'differs from source',
                               'unreadable-dylib': 'incorrect payload permissions',
                               'legacy-arm64e-abi': 'unversioned/unsupported arm64e ABI',
                               'unreviewed-dependency': 'control metadata differs',
                               'reordered-members': 'member order',
                               'compression-name-mismatch': 'compression does not match',
                               'extra-control-directory': 'unexpected package directory',
                               'extra-data-directory': 'unexpected package directory',
                               'trailing-file-slash': 'noncanonical package file path',
                               'boolean-profile': 'plist differs from source',
                               'duplicate-plist-key': 'duplicate plist dictionary key',
                               'missing-dependency': 'control metadata differs',
                               'duplicate-dependency': 'control metadata differs',
                               'missing-conflict': 'control metadata differs',
                               'split-control-stanza': 'multiple control stanzas',
                               **{label: 'uncompressed tar' for label in (
                                   'nested-control-gzip', 'nested-control-xz', 'nested-data-gzip', 'nested-data-xz',
                                   'tar-trailer-control', 'tar-trailer-data', 'tar-eof-control', 'tar-eof-data')}}[scenario]
            assert expected_reason in str(error), f'{scenario} failed for an unrelated reason: {error}'
        else:
            raise AssertionError(f'actual DEB mutation {scenario} was accepted')
        print(f'Actual built DEB: {scenario} rejected PASS')
        if scenario == 'boolean-profile':
            try:
                with contextlib.redirect_stdout(io.StringIO()): verify(path, version)
            except AssertionError as error:
                assert 'profile values/types differ' in str(error), str(error)
            else:
                raise AssertionError('boolean profile bypassed standalone schema verification')
            print('Actual built DEB: boolean profile rejected without a source checkout PASS')
        if scenario in ('unreviewed-dependency', 'missing-dependency', 'duplicate-dependency', 'missing-conflict'):
            try:
                with contextlib.redirect_stdout(io.StringIO()): verify(path, version)
            except AssertionError as error:
                assert ('package Conflicts differs' if scenario == 'missing-conflict' else 'package Depends differs') in str(error), str(error)
            else:
                raise AssertionError(f'{scenario} bypassed standalone control policy')
            print(f'Actual built DEB: {scenario} rejected without a source checkout PASS')
