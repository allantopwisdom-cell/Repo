"""Plist verification must preserve property-list types and reject duplicate keys."""
import plistlib
from pathlib import Path
import struct
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from verify_package import load_plist, plist_equal


class PlistValidation(unittest.TestCase):
    def test_xml_binary_and_dictionary_order_preserve_types(self):
        value = {'integer': 1, 'boolean': True, 'real': 1.0,
                 'nested': [0, False, 0.0, '0', b'0']}
        for fmt in (plistlib.FMT_XML, plistlib.FMT_BINARY):
            result = load_plist(plistlib.dumps(value, fmt=fmt))
            self.assertTrue(plist_equal(result, dict(reversed(list(value.items())))))
            self.assertIs(type(result['integer']), int)
            self.assertIs(type(result['boolean']), bool)
            self.assertIs(type(result['real']), float)

    def test_nested_equal_numeric_values_do_not_match_other_types(self):
        for expected, actual in ((0, False), (1, True), (0, 0.0), (False, 0), (1.0, 1),
                                 ([1], [True]), ({'x': [1]}, {'x': [True]}),
                                 ('1', b'1'), ([1], (1,)), ({'x': 0}, {'x': 0, 'y': 0})):
            with self.subTest(expected=expected, actual=actual):
                self.assertFalse(plist_equal(actual, expected))

    def test_duplicate_xml_keys_cannot_disappear_during_parsing(self):
        for last in ('<integer>0</integer>', '<false/>'):
            blob = ('<?xml version="1.0"?><plist version="1.0"><dict>'
                    '<key>PowerMode</key><integer>0</integer>'
                    '<key>PowerMode</key>' + last + '</dict></plist>').encode()
            with self.assertRaisesRegex(AssertionError, 'duplicate plist'):
                load_plist(blob)

    def test_duplicate_binary_keys_cannot_disappear_during_parsing(self):
        # Two references to the same key in a valid binary dictionary object.
        for second in (b'\x10\x00', b'\x10\x01'):
            objects = [b'\x59PowerMode', b'\x10\x00', second, b'\xd2\x00\x00\x01\x02']
            data = bytearray(b'bplist00')
            offsets = []
            for item in objects:
                offsets.append(len(data)); data.extend(item)
            table = len(data); data.extend(bytes(offsets))
            data.extend(struct.pack('>6xBBQQQ', 1, 1, len(objects), 3, table))
            with self.assertRaisesRegex(AssertionError, 'duplicate plist'):
                load_plist(bytes(data))


if __name__ == '__main__':
    unittest.main()
