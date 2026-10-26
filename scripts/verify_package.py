#!/usr/bin/env python3
"""Inspect Debian/Mach-O bytes without extracting as root. Fails closed for this project."""
import argparse
import hashlib
import io
from pathlib import Path
import plistlib
import struct
import tarfile

if not __debug__:
    raise RuntimeError("Package validation requires Python without -O")
from macho_signature import verify_signature


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


def tar_members(data):
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:*') as archive:
        result, seen = {}, set()
        for item in archive:
            name = item.name.removeprefix('./').rstrip('/')
            assert name == '.' and item.isdir() or all(part not in ('', '.', '..') for part in name.split('/')), 'unsafe/noncanonical package path'
            assert name not in seen, 'duplicate archive path'
            seen.add(name)
            assert item.isdir() or item.isfile(), 'links and special files are forbidden'
            assert (item.uid, item.gid) == (0, 0) and not item.mode & 0o7022, 'unsafe numeric ownership or permissions'
            if item.isdir():
                assert item.mode == 0o755, 'package directory must be traversable mode 0755'
                continue
            result[name] = (item, archive.extractfile(item).read())
        return result


def verify(path, expected_version):
    members = ar_members(path)
    control_name, = [key for key in members if key.startswith('control.tar.')]
    data_name, = [key for key in members if key.startswith('data.tar.')]
    assert set(members) == {'debian-binary', control_name, data_name}, 'unexpected ar member'
    controls, files = tar_members(members[control_name]), tar_members(members[data_name])
    assert set(controls) <= {'control', 'postinst', 'prerm', 'postrm', 'md5sums'}, 'unexpected control script'
    control = controls['control'][1].decode()
    fields = {}
    for line in control.splitlines():
        if not line or line[0].isspace():
            continue
        key, value = line.split(':', 1)
        assert key not in fields, f'duplicate control field: {key}'
        fields[key] = value.strip()
    assert fields['Package'] == 'com.minis.powercuff-baldaran-trusted'
    assert fields['Architecture'] == 'iphoneos-arm64e'
    assert fields['Version'] == expected_version, fields['Version']
    for name in ('postinst', 'prerm', 'postrm'):
        item, contents = controls[name]
        assert item.mode & 0o111 == 0o111, f'{name} not executable'
        assert contents.startswith(b'#!/bin/sh\n')
        assert b'killall -9' not in contents and b'defaults write' not in contents
    lib = 'Library/MobileSubstrate/DynamicLibraries/PowercuffBaldaranTrusted'
    panel_path = 'Library/PreferenceLoader/Preferences/PowercuffBaldaranTrusted/'
    expected_files = {lib + '.dylib', lib + '.plist'} | {panel_path + name for name in
                     ('Powercuff.plist', 'icon.png', 'Powercuff@2x.png', 'Powercuff@3x.png')}
    assert set(files) == expected_files, 'unexpected or missing package payload'
    item, binary = files[lib + '.dylib']
    magic, cpu, subtype, filetype, ncmds, cmdsize, flags, reserved = struct.unpack_from('<8I', binary)
    assert magic == 0xFEEDFACF and cpu == 0x0100000C and (subtype & 0xFFFFFF) == 2, 'not thin arm64e'
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
    assert imports and all(name.startswith(('/System/Library/', '/usr/lib/', '@loader_path/.jbroot/')) for name in imports), 'unexpected dylib dependency path'
    assert signed, 'code signature blob missing'
    assert offset == 32 + cmdsize, 'load command size mismatch'
    verify_signature(binary, *signature_range)
    assert install_id == '@loader_path/.jbroot/' + lib + '.dylib', f'non-RootHide install id: {install_id}'
    injection = plistlib.loads(files[lib + '.plist'][1])
    assert injection == {'Filter': {'Executables': ['SpringBoard', 'thermalmonitord']}}
    panel = plistlib.loads(files['Library/PreferenceLoader/Preferences/PowercuffBaldaranTrusted/Powercuff.plist'][1])
    preferences = {item['key']: item for item in panel['items'] if 'key' in item}
    assert preferences['PowerMode']['validValues'] == list(range(5))
    assert preferences['PowerMode']['default'] == 0
    assert preferences['RequireLowPowerMode']['default'] is False
    for pref in preferences.values():
        assert pref['defaults'] == fields['Package']
        assert pref['PostNotification'] == fields['Package'] + '.settingschanged'
    print(f'PASS {path}: version={fields["Version"]}, thin arm64e, CodeDirectory code/special hashes, iOS deployment, payload allowlist, RootHide paths, preferences, scripts')
    print('SHA256 ' + hashlib.sha256(Path(path).read_bytes()).hexdigest())


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('package')
    parser.add_argument('--version', required=True)
    args = parser.parse_args()
    verify(args.package, args.version)
