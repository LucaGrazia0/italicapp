import contextlib
import importlib.util
import io
import json
import re
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / 'prepare_offline_web.py'
spec = importlib.util.spec_from_file_location('offline_pack', SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class OfflinePackTests(unittest.TestCase):
    def fixture(self, root):
        paths = {
            'index.html', 'flutter_bootstrap.js', 'flutter.js', 'main.dart.js',
            'italic_offline.js', 'manifest.json', 'favicon.png',
            'canvaskit/canvaskit.js', 'canvaskit/canvaskit.wasm',
            'assets/AssetManifest.bin', 'assets/AssetManifest.bin.json',
            'assets/FontManifest.json', 'assets/NOTICES',
            'icons/Icon-192.png', 'icons/Icon-512.png',
            'icons/Icon-maskable-192.png', 'icons/Icon-maskable-512.png',
            'assets/fonts/icons.otf', 'assets/shaders/ink_sparkle.frag',
        }
        pubspec = SCRIPT.parents[1] / 'pubspec.yaml'
        paths.update('assets/' + m[1] for m in re.finditer(
            r'^\s+- (?:asset: )?(assets/[^\s]+)$', pubspec.read_text(), re.M))
        for path in paths:
            file = root / path
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text('fixture')
        (root / 'assets/FontManifest.json').write_text(json.dumps([
            {'family':'Icons', 'fonts':[{'asset':'fonts/icons.otf'}]}]))
        (root / 'assets/assets/italic/old_checklist 3.json').write_text('stale')
        (root / 'canvaskit/canvaskit 2.wasm').write_text('duplicate')
        return paths

    def prepare(self, root):
        with contextlib.redirect_stdout(io.StringIO()):
            return module.prepare(root)

    def test_pack_is_complete_deterministic_and_excludes_old_build_leftovers(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            paths = self.fixture(root)
            pack = self.prepare(root)
            self.assertEqual({r['path'] for r in pack['resources']}, paths)
            self.assertEqual(self.prepare(root), pack)
            self.assertNotIn('/*__ITALIC_PACK__*/ null', (root / 'italic_offline_worker.js').read_text())
            (root / 'main.dart.js').write_text('new build')
            self.assertNotEqual(self.prepare(root)['version'], pack['version'])

    def test_missing_resource_does_not_generate_a_partial_worker(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.fixture(root)
            (root / 'canvaskit/canvaskit.wasm').unlink()
            with self.assertRaises(FileNotFoundError):
                self.prepare(root)
            self.assertFalse((root / 'italic_offline_worker.js').exists())
