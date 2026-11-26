"""Launch the portable desktop edition on a fixed loopback origin."""

import argparse
import functools
import hashlib
import json
import sys
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WEB = ROOT / 'web'
ADDRESS = ('127.0.0.1', 8782)  # Preserve the origin of the previous Mac edition.
HEALTH = '__italic_go_desktop_status__'


def descriptor():
    return {**json.loads((ROOT / 'EDIZIONE.json').read_text(encoding='utf-8')),
            'directory': str(WEB.resolve())}


def verify_files(full=False):
    info = descriptor()
    manifest = json.loads((ROOT / 'CONTENUTO.json').read_text(encoding='utf-8'))
    required = {'web/index.html', 'web/main.dart.js', 'web/flutter_bootstrap.js',
                'web/italic_offline_worker.js', 'web/canvaskit/canvaskit.wasm'}
    files = manifest['files']
    if not required.issubset({f['path'] for f in files}):
        raise ValueError('Manifesto incompleto')
    for entry in files:
        relative = Path(entry['path'])
        if relative.is_absolute() or '..' in relative.parts:
            raise ValueError('Percorso non valido nel manifesto')
        if full or entry['path'] in required:
            content = (ROOT / relative).read_bytes()
            if hashlib.sha256(content).hexdigest() != entry['sha256']:
                raise ValueError('File mancante o modificato: ' + entry['path'])
    return info


class Handler(SimpleHTTPRequestHandler):
    extensions_map = {**SimpleHTTPRequestHandler.extensions_map,
                      '.wasm': 'application/wasm', '.webp': 'image/webp',
                      '.woff2': 'font/woff2',
                      '.js': 'text/javascript; charset=utf-8',
                      '.json': 'application/json; charset=utf-8'}

    def allowed(self):
        host = self.headers.get('Host', '')
        port = self.server.server_address[1]
        if host not in (f'127.0.0.1:{port}', f'localhost:{port}'):
            self.send_error(403, 'Solo accesso locale')
            return False
        path = urllib.parse.unquote(urllib.parse.urlsplit(self.path).path)
        if '..' in path.split('/') or '\\' in path:
            self.send_error(403, 'Percorso non consentito')
            return False
        return True

    def do_GET(self):
        if not self.allowed():
            return
        if urllib.parse.urlsplit(self.path).path == '/' + HEALTH:
            payload = json.dumps(descriptor()).encode('utf-8')
            self.send_response(200)
            self.send_header('Content-Type', 'application/json; charset=utf-8')
            self.send_header('Content-Length', str(len(payload)))
            self.send_header('Cache-Control', 'no-store')
            self.end_headers()
            self.wfile.write(payload)
        else:
            super().do_GET()

    def do_HEAD(self):
        if self.allowed():
            super().do_HEAD()

    def end_headers(self):
        if urllib.parse.urlsplit(self.path).path in (
                '/', '/index.html', '/flutter_bootstrap.js', '/main.dart.js',
                '/italic_offline_worker.js', '/flutter_service_worker.js'):
            self.send_header('Cache-Control', 'no-cache')
        self.send_header('X-Content-Type-Options', 'nosniff')
        super().end_headers()

    def list_directory(self, path):
        self.send_error(403, 'Elenco dei file non disponibile')
        return None

    def log_message(self, format, *args):
        if len(args) > 1 and str(args[1]).startswith(('4', '5')):
            super().log_message(format, *args)


class LocalServer(ThreadingHTTPServer):
    # On Windows, SO_REUSEADDR can permit a second process on an occupied port.
    allow_reuse_address = sys.platform != 'win32'
    daemon_threads = True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--verify', action='store_true', help='Verifica tutti i file')
    parser.add_argument('--no-browser', action='store_true')
    args = parser.parse_args()
    try:
        expected = verify_files(full=args.verify)
    except (OSError, ValueError, KeyError) as error:
        print('Pacchetto incompleto o modificato: ' + str(error), file=sys.stderr)
        print('Estrai nuovamente lo ZIP completo e riprova.', file=sys.stderr)
        return 1
    print(f"\nItalic Go {expected['version']} · edizione portatile {expected['platform']}", flush=True)
    url = f'http://{ADDRESS[0]}:{ADDRESS[1]}/'
    if args.check or args.verify:
        print('Verifica completata. Indirizzo: ' + url)
        return 0
    try:
        server = LocalServer(ADDRESS, functools.partial(Handler, directory=str(WEB)))
    except OSError as error:
        try:
            opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
            with opener.open(url + HEALTH, timeout=2) as response:
                existing = json.load(response)
        except (OSError, ValueError, urllib.error.URLError):
            existing = None
        if existing != expected:
            print(f'La porta {ADDRESS[1]} è occupata o non disponibile ({error}).', file=sys.stderr)
            print('Chiudi la precedente finestra di Italic Go con Ctrl+C e riprova.', file=sys.stderr)
            return 1
        print('Italic Go è già aperta: riapro la stessa edizione.', flush=True)
        if not args.no_browser:
            webbrowser.open(url)
        return 0
    with server:
        print(url, flush=True)
        print('Lascia aperta questa finestra durante l’uso. Per terminare premi Ctrl+C.', flush=True)
        print('Usa sempre lo stesso browser e indirizzo per ritrovare il diario.\n', flush=True)
        if not args.no_browser:
            webbrowser.open(url)
        try:
            server.serve_forever(poll_interval=.25)
        except KeyboardInterrupt:
            print('\nItalic Go chiusa. Il diario resta salvato nel browser.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
