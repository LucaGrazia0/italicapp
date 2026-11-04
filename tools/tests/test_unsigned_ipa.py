import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import struct
import tempfile
import unittest
import zipfile

SCRIPT = Path(__file__).resolve().parents[1] / 'package_unsigned_ipa.py'
spec = importlib.util.spec_from_file_location('ipa', SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class IpaTests(unittest.TestCase):
    def fixture(self, root, platform=2):
        app = root / 'Runner.app'
        app.mkdir()
        (app / 'Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': 'it.italic.italicapp',
            'CFBundleShortVersionString': '0.8.10', 'CFBundleVersion': '23',
            'CFBundleSupportedPlatforms': ['iPhoneOS'], 'CFBundleExecutable': 'Runner'}))
        header = struct.pack('<8I', 0xfeedfacf, 0x100000c, 0, 2, 1, 24, 0, 0)
        (app / 'Runner').write_bytes(header + struct.pack('<6I', 0x32, 24, platform, 0, 0, 0))
        assets = app / 'Frameworks/App.framework/flutter_assets'
        (assets / 'assets/italic').mkdir(parents=True)
        (assets / 'assets/photos').mkdir()
        photo = assets / 'assets/photos/example.webp'
        photo.write_bytes(b'photo')
        (assets / 'assets/italic/species_photos_v1.json').write_text(json.dumps({'photos': [{
            'italicId': 3072, 'asset': 'assets/photos/example.webp',
            'sha256': hashlib.sha256(b'photo').hexdigest()}]}))
        return app

    def package(self, app, root):
        with contextlib.redirect_stdout(io.StringIO()):
            return module.package(app, root / 'out.ipa', '0.8.10', '23')

    def test_real_device_payload_and_local_photos_are_packaged_with_provenance(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            report = self.package(self.fixture(root), root)
            self.assertFalse(report['signedForInstallation'])
            self.assertEqual(report['photoChecksumsVerified'], 1)
            with zipfile.ZipFile(root / 'out.ipa') as archive:
                self.assertIn('Payload/Runner.app/Runner', archive.namelist())
                self.assertEqual(archive.read('Payload/Runner.app/Frameworks/App.framework/flutter_assets/assets/photos/example.webp'), b'photo')

    def test_simulator_binary_cannot_be_presented_as_an_iphone_ipa(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            with self.assertRaises(ValueError):
                self.package(self.fixture(root, platform=7), root)
            self.assertFalse((root / 'out.ipa').exists())

    def test_wrong_release_or_missing_photo_prevents_packaging(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            app = self.fixture(root)
            with self.assertRaises(ValueError):
                module.package(app, root / 'out.ipa', '0.8.9', '23')
            (app / 'Frameworks/App.framework/flutter_assets/assets/photos/example.webp').write_bytes(b'wrong photo')
            with self.assertRaises(ValueError):
                self.package(app, root)
            self.assertFalse((root / 'out.ipa').exists())


if __name__ == '__main__':
    unittest.main()
