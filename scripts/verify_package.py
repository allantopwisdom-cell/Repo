#!/usr/bin/env python3
"""Inspect Debian/Mach-O bytes without extracting as root. Fails closed for this project."""
import argparse
from contextlib import contextmanager
import gzip
import hashlib
import io
import lzma
from pathlib import Path
import plistlib
import re
import struct
import tarfile

if not __debug__:
    raise RuntimeError("Package validation requires Python without -O")
from macho_signature import verify_signature

LIBRARY = 'Library/MobileSubstrate/DynamicLibraries/PowercuffBaldaranTrusted'
PANEL_PATH = 'Library/PreferenceLoader/Preferences/PowercuffBaldaranTrusted/'
CONTROL_FILES = {'control', 'postinst', 'prerm', 'postrm'}
PAYLOAD_FILES = {LIBRARY + '.dylib', LIBRARY + '.plist'} | {PANEL_PATH + name for name in
                 ('Powercuff.plist', 'icon.png', 'Powercuff@2x.png', 'Powercuff@3x.png')}
EXPECTED_DEPENDS = {'mobilesubstrate (>= 0.9.9000)', 'preferenceloader',
                    'firmware (>= 16.0)', 'firmware (<< 17.0)'}
EXPECTED_CONFLICTS = {'com.rpetrich.powercuff', 'com.baldaran.powercuff-r3vamp',
                      'com.minis.powercuff-r3vamp-roothide', 'com.minis.powercuff-r3vamp-trusted'}


class UniquePlistDictionary(dict):
    """Reject ambiguous dictionaries before a parser can discard a duplicate."""
    def __setitem__(self, key, value):
        assert type(key) is str, 'plist dictionary keys must be strings'
        assert key not in self, 'duplicate plist dictionary key'
        super().__setitem__(key, value)


def load_plist(contents):
    return plistlib.loads(contents, dict_type=UniquePlistDictionary)


def plist_equal(actual, expected):
    # Python bool/int/float equality erases distinctions that matter to Settings
    # and PCRValidatedMode. Accept XML/binary encodings, preserving plist types.
    if isinstance(expected, dict):
        return isinstance(actual, dict) and actual.keys() == expected.keys() and all(
            plist_equal(actual[key], value) for key, value in expected.items())
    if isinstance(expected, list):
        return type(actual) is list and len(actual) == len(expected) and all(
            plist_equal(a, b) for a, b in zip(actual, expected))
    return type(actual) is type(expected) and actual == expected


def ar_members(path):
    data = Path(path).read_bytes()
    assert data[:8] == b'!<arch>\n', 'not a Debian ar archive'
    offset, result = 8, {}
    while offset < len(data):
        header = data[offset:offset + 60]
        assert len(header) == 60 and header[58:] == b'`\n', 'invalid ar header'
        size = int(header[48:58])
        assert size >= 0, 'negative ar member size'
        name = header[:16].decode().strip().rstrip('/')
        payload = data[offset + 60:offset + 60 + size]
        assert len(payload) == size, 'truncated member'
        assert name not in result, 'duplicate ar member'
        result[name] = payload
        offset += 60 + size + (size & 1)
        assert offset <= len(data), 'missing ar padding'
        if size & 1:
            assert data[offset - 1:offset] == b'\n', 'invalid ar padding'
    assert result.get('debian-binary') == b'2.0\n'
    return result


def decompress_tar(name, data):
    suffix = name.rsplit('.', 1)[-1]
    assert suffix in ('gz', 'xz', 'lzma'), 'unsupported Debian compression suffix'
    try:
        return (gzip.decompress(data) if suffix == 'gz' else
                lzma.decompress(data, format=lzma.FORMAT_XZ if suffix == 'xz' else lzma.FORMAT_ALONE))
    except (OSError, EOFError, lzma.LZMAError) as error:
        raise AssertionError('Debian compression does not match member name') from error


@contextmanager
def uncompressed_tar(data):
    # Debian has one compression layer. Autodetection here would accept a second
    # layer that dpkg cannot parse. Also inspect bytes after tarfile's first EOF:
    # a successful member iteration alone silently ignores appended payloads.
    assert len(data) % 512 == 0, 'invalid uncompressed tar block framing'
    try:
        with tarfile.open(fileobj=io.BytesIO(data), mode='r:') as archive:
            archive.getmembers()
            trailer = data[archive.offset:]
            assert len(trailer) >= 1024 and not any(trailer), 'invalid uncompressed tar end markers/trailer'
            yield archive
    except (tarfile.TarError, EOFError) as error:
        raise AssertionError('invalid uncompressed tar archive') from error


def tar_members(data, allowed_files=None):
    allowed_directories = {'.'}
    if allowed_files is not None:
        for path in allowed_files:
            parts = path.split('/')
            allowed_directories.update('/'.join(parts[:i]) for i in range(1, len(parts)))
    with uncompressed_tar(data) as archive:
        result, seen = {}, set()
        for item in archive:
            assert item.isdir() or not item.name.endswith('/'), 'unsafe/noncanonical package file path'
            name = item.name.removeprefix('./').rstrip('/')
            assert name == '.' and item.isdir() or all(part not in ('', '.', '..') for part in name.split('/')), 'unsafe/noncanonical package path'
            assert name not in seen, 'duplicate archive path'
            seen.add(name)
            assert item.isdir() or item.isfile(), 'links and special files are forbidden'
            assert (item.uid, item.gid) == (0, 0) and not item.mode & 0o7022, 'unsafe numeric ownership or permissions'
            if item.isdir():
                assert item.mode == 0o755, 'package directory must be traversable mode 0755'
                assert allowed_files is None or name in allowed_directories, 'unexpected package directory'
                continue
            assert allowed_files is None or name in allowed_files, 'unexpected package file'
            result[name] = (item, archive.extractfile(item).read())
        return result


def package_archives(members, allowed_files=None):
    names = list(members)
    assert len(names) == 3 and names[0] == 'debian-binary', 'incorrect Debian member order/count'
    result = []
    for name, prefix in zip(names[1:], ('control.tar.', 'data.tar.')):
        assert name.startswith(prefix), 'incorrect Debian member order'
        raw = decompress_tar(name, members[name])
        result.append(tar_members(raw, allowed_files[len(result)] if allowed_files is not None else None))
    return tuple(result)


def control_fields(contents):
    text = contents.decode('utf-8').replace('\r\n', '\n')
    assert all(c in '\t\n' or ord(c) >= 32 and ord(c) != 127 for c in text), 'invalid control character'
    fields, current, seen, ended = {}, None, set(), False
    # Debian binary metadata is one stanza with LF/CRLF physical lines. Unicode
    # splitlines()/isspace() would give a different interpretation from dpkg.
    for line in text.split('\n'):
        if not line.strip(' \t'):
            if fields: ended = True
            continue
        assert not ended, 'multiple control stanzas are forbidden'
        if line[0] in ' \t':
            assert current, 'control continuation without a field'
            fields[current] += '\n' + line[1:]
            continue
        assert ':' in line, 'control field has no separator'
        key, value = line.split(':', 1)
        assert re.fullmatch(r'[!-9;-~]+', key) and key[0] not in '#-', 'invalid control field name'
        assert key.lower() not in seen, f'duplicate control field: {key}'
        seen.add(key.lower())
        value = value.strip(' \t')
        assert value, 'empty binary control field'
        fields[key] = value
        current = key
    assert fields, 'empty binary control stanza'
    return fields


def verify_source_contents(controls, files, source_root):
    root = Path(source_root)
    generated = control_fields(controls['control'][1])
    installed_size = generated.pop('Installed-Size', None) # Added by Theos, not source control.
    if installed_size is not None:
        assert installed_size.isascii() and installed_size.isdecimal() and int(installed_size) > 0, 'invalid Installed-Size'
    assert generated == control_fields((root / 'control').read_bytes()), 'control metadata differs from source'
    for name in ('postinst', 'prerm', 'postrm'):
        assert controls[name][1] == (root / 'layout/DEBIAN' / name).read_bytes(), f'{name} differs from reviewed source'
    for name, (_, contents) in files.items():
        if name.endswith('.dylib'):
            continue
        source = root / ('PowercuffBaldaranTrusted.plist' if name.endswith('/PowercuffBaldaranTrusted.plist') else 'layout/' + name)
        expected = source.read_bytes()
        if name.endswith('.plist'):
            assert plist_equal(load_plist(contents), load_plist(expected)), f'{name} plist differs from source'
        else:
            assert contents == expected, f'{name} differs from source'


def verify(path, expected_version, source_root=None):
    members = ar_members(path)
    controls, files = package_archives(members, (CONTROL_FILES, PAYLOAD_FILES))
    assert set(controls) == CONTROL_FILES, 'unexpected or missing control file'
    fields = control_fields(controls['control'][1])
    assert fields['Package'] == 'com.minis.powercuff-baldaran-trusted'
    assert fields['Architecture'] == 'iphoneos-arm64e'
    assert fields['Version'] == expected_version, fields['Version']
    for name in ('postinst', 'prerm', 'postrm'):
        item, contents = controls[name]
        assert item.mode & 0o111 == 0o111, f'{name} not executable'
        assert contents.startswith(b'#!/bin/sh\n')
        assert b'killall -9' not in contents and b'defaults write' not in contents
    lib = LIBRARY
    assert set(files) == PAYLOAD_FILES, 'unexpected or missing package payload'
    for name, (item, _) in files.items():
        assert item.mode == (0o755 if name.endswith('.dylib') else 0o644), f'incorrect payload permissions: {name}'
    assert controls['control'][0].mode == 0o644, 'control metadata permissions'
    for name in ('postinst', 'prerm', 'postrm'):
        assert controls[name][0].mode == 0o755, f'{name} permissions'
    if source_root is not None:
        verify_source_contents(controls, files, source_root)
    for key, expected in (('Depends', EXPECTED_DEPENDS), ('Conflicts', EXPECTED_CONFLICTS)):
        entries = [value.strip() for value in fields.get(key, '').split(',')]
        assert len(entries) == len(expected) and set(entries) == expected, f'package {key} differs from reviewed policy'
    item, binary = files[lib + '.dylib']
    magic, cpu, subtype, filetype, ncmds, cmdsize, flags, reserved = struct.unpack_from('<8I', binary)
    assert magic == 0xFEEDFACF and cpu == 0x0100000C and (subtype & 0xFFFFFF) == 2, 'not thin arm64e'
    assert subtype == 0x80000002, 'unversioned/unsupported arm64e ABI; expected userland PAC00'
    assert filetype == 6 and ncmds > 0, 'not a dylib'
    offset, signed, install_id = 32, False, ''
    signature_range = None
    deployment, imports = None, []
    for _ in range(ncmds):
        cmd, size = struct.unpack_from('<2I', binary, offset)
        assert size >= 8 and size % 8 == 0 and offset + size <= 32 + cmdsize <= len(binary)
        if cmd == 0x32: # LC_BUILD_VERSION
            assert deployment is None and size >= 24, 'duplicate/truncated deployment command'
            deployment = struct.unpack_from('<II', binary, offset + 8)
        if cmd in (0xC, 0x20, 0x80000018, 0x8000001F, 0x80000023):
            assert size >= 24
            string_offset, = struct.unpack_from('<I', binary, offset + 8)
            assert 24 <= string_offset < size
            raw = binary[offset + string_offset:offset + size]
            assert b'\0' in raw
            imports.append(raw.split(b'\0')[0].decode())
        if cmd == 0x1D: # LC_CODE_SIGNATURE
            assert signature_range is None and size == 16, 'duplicate/truncated signature command'
            start, length = struct.unpack_from('<2I', binary, offset + 8)
            signed = length > 0 and start >= 32 + cmdsize and start + length == len(binary)
            signature_range = (start, length)
        if cmd == 0xD: # LC_ID_DYLIB
            assert size >= 24 and not install_id
            start, = struct.unpack_from('<I', binary, offset + 8)
            assert 24 <= start < size and b'\0' in binary[offset + start:offset + size]
            install_id = binary[offset + start:offset + size].split(b'\0')[0].decode()
        offset += size
    assert deployment == (2, 0x100000), 'expected iOS device platform and iOS 16.0 deployment target'
    expected_imports = {'/usr/lib/libobjc.A.dylib', '/usr/lib/libSystem.B.dylib',
                        '/System/Library/Frameworks/Foundation.framework/Foundation',
                        '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation',
                        '@loader_path/.jbroot/usr/lib/libsubstrate.dylib'}
    assert set(imports) == expected_imports and len(imports) == len(expected_imports), 'unexpected dylib dependencies'
    assert signed, 'code signature blob missing'
    assert offset == 32 + cmdsize, 'load command size mismatch'
    verify_signature(binary, *signature_range)
    assert install_id == '@loader_path/.jbroot/' + lib + '.dylib', f'non-RootHide install id: {install_id}'
    injection = load_plist(files[lib + '.plist'][1])
    assert plist_equal(injection, {'Filter': {'Executables': ['SpringBoard', 'thermalmonitord']}})
    panel = load_plist(files['Library/PreferenceLoader/Preferences/PowercuffBaldaranTrusted/Powercuff.plist'][1])
    keyed_items = [item for item in panel['items'] if 'key' in item]
    preferences = {item['key']: item for item in keyed_items}
    assert len(keyed_items) == 2 and set(preferences) == {'PowerMode', 'RequireLowPowerMode'}, 'unexpected/duplicate preference keys'
    assert plist_equal(preferences['PowerMode']['validValues'], list(range(5))), 'profile values/types differ'
    assert plist_equal(preferences['PowerMode']['validTitles'], ['关闭', '标称（仍在模拟）', '轻度', '中度', '重度']), 'profile titles differ'
    assert plist_equal(preferences['PowerMode']['default'], 0), 'profile default/type differs'
    assert preferences['RequireLowPowerMode']['default'] is False
    for pref in preferences.values():
        assert pref['defaults'] == fields['Package']
        assert pref['PostNotification'] == fields['Package'] + '.settingschanged'
    print(f'PASS {path}: version={fields["Version"]}, thin versioned arm64e PAC00, CodeDirectory code/special hashes, iOS deployment, payload allowlist, RootHide paths, preferences, scripts')
    print('SHA256 ' + hashlib.sha256(Path(path).read_bytes()).hexdigest())


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('package')
    parser.add_argument('--version', required=True)
    parser.add_argument('--source-root', help='Compare control metadata, scripts and static assets to this source checkout')
    args = parser.parse_args()
    verify(args.package, args.version, args.source_root)
