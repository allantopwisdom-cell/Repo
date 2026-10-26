#!/usr/bin/env python3
"""Negative tests against the actual signed Mach-O from this build."""
import struct
import sys
from verify_package import ar_members, tar_members
from macho_signature import verify_signature

members = ar_members(sys.argv[1])
name, = [n for n in members if n.startswith('data.tar.')]
files = tar_members(members[name])
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
