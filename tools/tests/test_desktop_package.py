import hashlib
import http.client
import importlib.util
import json
import tempfile
import threading
import unittest
from pathlib import Path
from functools import partial

TOOLS = Path(__file__).resolve().parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name, TOOLS / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class DesktopPackageTests(unittest.TestCase):
    def test_web_manifest_rejects_modified_resources_and_path_escape(self):
        package = load('package_desktop')
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'index.html').write_bytes(b'good')
            worker = root / 'italic_offline_worker.js'
            pack = {'version': 'test', 'resources': [
                {'path': 'index.html', 'sha256': hashlib.sha256(b'good').hexdigest()}]}
            worker.write_text('const PACK = ' + json.dumps(pack) + ';\n')
            (root / 'index.html').write_bytes(b'changed')
            with self.assertRaisesRegex(ValueError, 'modificata'):
                package.web_resources(root)
            pack['resources'][0]['path'] = '../outside'
            worker.write_text('const PACK = ' + json.dumps(pack) + ';\n')
            with self.assertRaisesRegex(ValueError, 'Percorso'):
                package.web_resources(root)

    def test_loopback_server_mime_host_and_traversal(self):
        launcher = load('launch_desktop')
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'index.html').write_text('Italic Go')
            (root / 'test.wasm').write_bytes(b'\0asm')
            (root / 'empty').mkdir()
            server = launcher.LocalServer(('127.0.0.1', 0), partial(launcher.Handler, directory=folder))
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            port = server.server_address[1]
            try:
                c = http.client.HTTPConnection('127.0.0.1', port, timeout=3)
                for path, host, expected in [('/', f'127.0.0.1:{port}', 200),
                                             ('/%2e%2e/outside', f'127.0.0.1:{port}', 403),
                                             ('/empty/', f'127.0.0.1:{port}', 403),
                                             ('/', 'external.example', 403)]:
                    c.request('GET', path, headers={'Host': host})
                    response = c.getresponse()
                    response.read()
                    self.assertEqual(response.status, expected)
                c.request('HEAD', '/test.wasm')
                response = c.getresponse()
                response.read()
                self.assertEqual(response.getheader('Content-Type'), 'application/wasm')
                c.close()
            finally:
                server.shutdown()
                server.server_close()
                thread.join(timeout=3)

    def test_critical_startup_files_are_checked_before_launch(self):
        launcher = load('launch_desktop')
        with tempfile.TemporaryDirectory() as folder:
            launcher.ROOT = Path(folder)
            launcher.WEB = launcher.ROOT / 'web'
            launcher.WEB.mkdir()
            (launcher.ROOT / 'EDIZIONE.json').write_text('{}')
            (launcher.ROOT / 'CONTENUTO.json').write_text('{"files": []}')
            with self.assertRaisesRegex(ValueError, 'Manifesto incompleto'):
                launcher.verify_files()


if __name__ == '__main__':
    unittest.main()
