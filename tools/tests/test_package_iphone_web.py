import hashlib
import importlib.util
import json
import tempfile
import unittest
import zipfile
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / 'package_iphone_web.py'
spec = importlib.util.spec_from_file_location('iphone_package', SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class IphonePackageTests(unittest.TestCase):
    def fixture(self, root):
        data = b'<base href="/italicapp/">'
        (root / 'index.html').write_bytes(data)
        pack = {'resources': [{'path': 'index.html', 'sha256': hashlib.sha256(data).hexdigest()}]}
        (root / 'italic_offline_worker.js').write_text('const PACK = ' + json.dumps(pack) + ';\n')
        (root / 'old.apk').write_text('excluded')
        (root / 'diary.json').write_text('excluded')

    def test_archive_contains_only_verified_application_files(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.fixture(root)
            destination = root / 'app.zip'
            module.package(root, destination)
            with zipfile.ZipFile(destination) as z:
                self.assertEqual(set(z.namelist()), {'index.html', 'italic_offline_worker.js'})
                self.assertEqual(z.read('index.html'), b'<base href="/italicapp/">')

    def test_changed_build_is_rejected_before_creating_the_archive(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.fixture(root)
            (root / 'index.html').write_text('changed')
            destination = root / 'app.zip'
            with self.assertRaises(ValueError):
                module.package(root, destination)
            self.assertFalse(destination.exists())
