"""Validate signing metadata as well as page and special-slot digest bytes."""
import hashlib
from pathlib import Path
import struct
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from macho_signature import verify_signature


class SignatureMetadata(unittest.TestCase):
    def fixture(self):
        code = b'synthetic signed code bytes'
        identifier = b'Powercuff-test\0'
        requirements = struct.pack('>3I', 0xFADE0C01, 12, 0)
        hash_offset = 88 + len(identifier) + 40
        directory = bytearray(hash_offset + 20)
        struct.pack_into('>9I', directory, 0, 0xFADE0C02, len(directory), 0x20400, 0,
                         hash_offset, 88, 2, 1, len(code))
        struct.pack_into('>4B', directory, 36, 20, 1, 0, 12)
        directory[88:88 + len(identifier)] = identifier
        directory[hash_offset - 40:hash_offset - 20] = hashlib.sha1(requirements).digest()
        directory[hash_offset:] = hashlib.sha1(code).digest()
        signature = bytearray(struct.pack('>7I', 0xFADE0CC0, 28 + len(directory) + len(requirements),
                                          2, 0, 28, 2, 28 + len(directory)))
        signature.extend(directory); signature.extend(requirements)
        return bytearray(code + signature), len(code), len(signature), len(code) + 28

    def test_valid_standalone_signature(self):
        binary, offset, size, _ = self.fixture()
        self.assertEqual(verify_signature(binary, offset, size), 1)

    def test_special_coverage_cannot_hide_requirements(self):
        for special in (0, 1, 3, 7):
            binary, offset, size, cd = self.fixture()
            struct.pack_into('>I', binary, cd + 24, special)
            with self.assertRaisesRegex(AssertionError, 'special-slot'):
                verify_signature(binary, offset, size)

    def test_unsupported_extensions_and_versions(self):
        for relative, value in ((8, 0xFFFFFF), (12, 0x4000000), (40, 1), (44, 1), (48, 1), (52, 1), (92, 1)):
            binary, offset, size, cd = self.fixture()
            if relative == 92:
                struct.pack_into('>I', binary, cd + 8, 0x20500)
            struct.pack_into('>I', binary, cd + relative, value)
            with self.assertRaises(AssertionError):
                verify_signature(binary, offset, size)

    def test_extended_limit_and_exec_policy(self):
        for relative, value in ((56, 1234), (64, 1000), (72, 1000), (80, 0x10)):
            binary, offset, size, cd = self.fixture()
            struct.pack_into('>Q', binary, cd + relative, value)
            with self.assertRaises(AssertionError):
                verify_signature(binary, offset, size)

    def test_identifier_and_requirements_types(self):
        binary, offset, size, cd = self.fixture()
        struct.pack_into('>I', binary, cd + 20, 88 + len(b'Powercuff-test\0') + 1)
        with self.assertRaisesRegex(AssertionError, 'identifier'):
            verify_signature(binary, offset, size)
        binary, offset, size, cd = self.fixture()
        struct.pack_into('>I', binary, offset + size - 12, 0xFADE7171)
        with self.assertRaisesRegex(AssertionError, 'requirements vector'):
            verify_signature(binary, offset, size)

    def test_truncated_versioned_header(self):
        binary, offset, size, cd = self.fixture()
        struct.pack_into('>I', binary, cd + 8, 0x20600)
        struct.pack_into('>I', binary, cd + 4, 44)
        with self.assertRaisesRegex(AssertionError, 'versioned'):
            verify_signature(binary, offset, size)
