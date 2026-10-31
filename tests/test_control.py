"""Binary control parsing must agree with Debian stanza and field semantics."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from verify_package import control_fields


class BinaryControlValidation(unittest.TestCase):
    def test_one_stanza_preserves_description_and_horizontal_whitespace(self):
        for ending in ('\n', '\r\n'):
            value = ending.join(('', 'Name:\tPowercuff  ', 'Description: first', ' second', ' .', ' third', '', ''))
            self.assertEqual(control_fields(value.encode()),
                             {'Name': 'Powercuff', 'Description': 'first\nsecond\n.\nthird'})

    def test_fields_cannot_continue_after_a_stanza_separator(self):
        for separator in ('\n\n', '\n \n', '\n\t\n'):
            with self.subTest(separator=repr(separator)), self.assertRaisesRegex(AssertionError, 'stanza'):
                control_fields(('Package: example' + separator + 'Version: 1\n').encode())

    def test_field_names_are_case_insensitive_for_duplicate_detection(self):
        for second in ('package', 'PACKAGE', 'PaCkAgE'):
            with self.subTest(second=second), self.assertRaisesRegex(AssertionError, 'duplicate'):
                control_fields(('Package: example\n' + second + ': example\n').encode())

    def test_invalid_field_names_values_and_control_characters_are_rejected(self):
        values = ('Bad Name: x\n', '-Name: x\n', '#Name: x\n', '名字: x\n', ': x\n',
                  'Name: \t\n', 'Name: x\x00\n', 'Name: x\x0bVersion: 2\n', 'Name: x\rVersion: 2\n')
        for value in values:
            with self.subTest(value=repr(value)), self.assertRaises(AssertionError):
                control_fields(value.encode())

    def test_unicode_line_separators_do_not_create_debian_fields(self):
        for separator in ('\u0085', '\u2028', '\u2029'):
            self.assertEqual(control_fields(('Description: first' + separator + 'Name: literal\n').encode()),
                             {'Description': 'first' + separator + 'Name: literal'})
