#!/usr/bin/env python3
"""Inspect Debian/Mach-O bytes without extracting as root. Fails closed for this project."""
import argparse
import hashlib
import io
from pathlib import Path
import plistlib
import struct
import tarfile


def ar_members(path):
    data = Path(path).read_bytes()
    assert data[:8] == b'!<arch>\n', 'not a Debian ar archive'
    offset, result = 8, {}
    while offset < len(data):
        header = data[offset:offset + 60]
        assert len(header) == 60 and header[58:] == b'`\n', 'invalid ar header'
        size = int(header[48:58])
        name = header[:16].decode().strip().rstrip('/')
        payload = data[offset + 60:offset + 60 + size]
        assert len(payload) == size, 'truncated member'
        assert name not in result, 'duplicate ar member'
        result[name] = payload
        offset += 60 + size + (size & 1)
    assert result.get('debian-binary') == b'2.0\n'
    return result


def tar_members(data):
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:*') as archive:
        result = {}
        for item in archive:
            name = item.name.removeprefix('./').rstrip('/')
            assert not name.startswith('/') and '..' not in name.split('/'), 'unsafe package path'
            if not item.isfile():
                continue
            assert name not in result, 'duplicate file'
            result[name] = (item, archive.extractfile(item).read())
        return result


def verify(path, expected_version):
    members = ar_members(path)
    control_name, = [key for key in members if key.startswith('control.tar.')]
    data_name, = [key for key in members if key.startswith('data.tar.')]
    controls, files = tar_members(members[control_name]), tar_members(members[data_name])
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
    item, binary = files[lib + '.dylib']
    magic, cpu, subtype, filetype, ncmds, cmdsize, flags, reserved = struct.unpack_from('<8I', binary)
    assert magic == 0xFEEDFACF and cpu == 0x0100000C and (subtype & 0xFFFFFF) == 2, 'not thin arm64e'
    assert filetype == 6 and ncmds > 0, 'not a dylib'
    offset, signed, install_id = 32, False, ''
    for _ in range(ncmds):
        cmd, size = struct.unpack_from('<2I', binary, offset)
        assert size >= 8 and offset + size <= 32 + cmdsize <= len(binary)
        if cmd == 0x1D: # LC_CODE_SIGNATURE
            start, length = struct.unpack_from('<2I', binary, offset + 8)
            signed = length > 0 and start + length <= len(binary)
        if cmd == 0xD: # LC_ID_DYLIB
            start, = struct.unpack_from('<I', binary, offset + 8)
            install_id = binary[offset + start:offset + size].split(b'\0')[0].decode()
        offset += size
    assert signed, 'code signature blob missing (cryptographic validity requires ldid/device)'
    assert install_id.startswith('@loader_path/.jbroot/'), f'non-RootHide install id: {install_id}'
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
    print(f'PASS {path}: version={fields["Version"]}, thin arm64e, signature blob, RootHide install id, filters, preferences, scripts')
    print('SHA256 ' + hashlib.sha256(Path(path).read_bytes()).hexdigest())


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('package')
    parser.add_argument('--version', required=True)
    args = parser.parse_args()
    verify(args.package, args.version)
