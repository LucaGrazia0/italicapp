"""Build a verified offline pack after `flutter build web --no-pub`.

Explicit asset manifests exclude stale build leftovers and duplicate cloud files.
No user IndexedDB data, remote pages, or downloaded descriptions are included.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path


def prepare(root: Path):
    paths = {'index.html', 'flutter_bootstrap.js', 'flutter.js', 'main.dart.js',
             'italic_offline.js', 'manifest.json', 'favicon.png',
             'canvaskit/canvaskit.js', 'canvaskit/canvaskit.wasm',
             'assets/AssetManifest.bin', 'assets/AssetManifest.bin.json',
             'assets/FontManifest.json', 'assets/NOTICES'}
    # pubspec declarations here are scalar asset paths. Generated package fonts
    # and renderer shaders are included separately. Fail on missing resources.
    pubspec = Path(__file__).resolve().parents[1] / 'pubspec.yaml'
    for match in re.finditer(r'^\s+- (?:asset: )?(assets/[^\s]+)$', pubspec.read_text(), re.M):
        paths.add('assets/' + match[1])
    for family in json.loads((root / 'assets/FontManifest.json').read_text()):
        for font in family['fonts']:
            paths.add('assets/' + font['asset'])
    for path in (root / 'assets/shaders').glob('*.frag'):
        if ' ' not in path.name:
            paths.add(path.relative_to(root).as_posix())
    paths.update('icons/' + name for name in (
        'Icon-192.png', 'Icon-512.png', 'Icon-maskable-192.png', 'Icon-maskable-512.png'))
    resources = []
    size = 0
    for path in sorted(paths):
        data = (root / path).read_bytes()  # Fail closed on missing build resources.
        resources.append({'path': path, 'sha256': hashlib.sha256(data).hexdigest()})
        size += len(data)
    version = hashlib.sha256(json.dumps(resources, sort_keys=True).encode()).hexdigest()[:20]
    pack = {'version': version, 'bytes': size, 'resources': resources}
    template = (Path(__file__).resolve().parents[1] / 'web/italic_offline_worker.js').read_text()
    (root / 'italic_offline_worker.js').write_text(template.replace('/*__ITALIC_PACK__*/ null', json.dumps(pack)))
    print(f'Offline: {len(resources)} risorse, {size / 1024 / 1024:.1f} MB, versione {version}')
    return pack


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('build', nargs='?', default='build/web', type=Path)
    prepare(parser.parse_args().build)
