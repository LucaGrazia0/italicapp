import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest
import zipfile

SCRIPT = Path(__file__).resolve().parents[1] / 'verify_android_startup.py'
spec = importlib.util.spec_from_file_location('startup', SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def dex(names, defined):
    # The fixture includes referenced-but-undefined types, the failure in 0.8.21.
    sa, ta = 112, 112 + 4 * len(names)
    ca = ta + 4 * len(names)
    text_at = ca + 32 * len(defined)
    data = bytearray(text_at)
    data[:8] = b'dex\n037\x00'
    struct.pack_into('<II', data, 0x38, len(names), sa)
    struct.pack_into('<II', data, 0x40, len(names), ta)
    struct.pack_into('<II', data, 0x60, len(defined), ca)
    for i, name in enumerate(names):
        struct.pack_into('<I', data, sa + 4 * i, len(data))
        struct.pack_into('<I', data, ta + 4 * i, i)
        data.extend(bytes([len(name)]) + name.encode() + b'\0')
    for i, index in enumerate(defined):
        struct.pack_into('<I', data, ca + 32 * i, index)
    return bytes(data)


class AndroidStartupTests(unittest.TestCase):
    def test_a_reference_to_the_registrant_does_not_prove_it_is_compiled(self):
        names = sorted(module.REQUIRED)
        absent = names.index('Lio/flutter/plugins/GeneratedPluginRegistrant;')
        data = dex(names, [i for i in range(len(names)) if i != absent])
        self.assertIn(b'GeneratedPluginRegistrant', data)
        self.assertNotIn('Lio/flutter/plugins/GeneratedPluginRegistrant;', module.dex_classes(data))
        with tempfile.TemporaryDirectory() as d:
            apk = Path(d) / 'broken.apk'
            with zipfile.ZipFile(apk, 'w') as z:
                z.writestr('classes.dex', data)
            with self.assertRaisesRegex(ValueError, 'GeneratedPluginRegistrant'):
                module.verify(apk)

    def test_multiple_dex_files_can_supply_the_required_definitions(self):
        names = sorted(module.REQUIRED)
        with tempfile.TemporaryDirectory() as d:
            apk = Path(d) / 'working.apk'
            with zipfile.ZipFile(apk, 'w') as z:
                z.writestr('classes.dex', dex(names, [0, 1]))
                z.writestr('classes2.dex', dex(names, [2]))
            self.assertEqual(module.verify(apk)['startupClassesVerified'], names)

    def test_malformed_class_tables_are_rejected(self):
        with self.assertRaises(ValueError):
            module.dex_classes(b'not a dex file')
        data = bytearray(dex(['LTest;'], [0]))
        struct.pack_into('<I', data, 0x64, len(data))
        with self.assertRaises(ValueError):
            module.dex_classes(bytes(data))


if __name__ == '__main__':
    unittest.main()
