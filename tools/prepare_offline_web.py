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
    # Photo directories use an explicit catalogue, not all build leftovers.
    pubspec = Path(__file__).resolve().parents[1] / 'pubspec.yaml'
    for match in re.finditer(r'^\s+- (?:asset: )?(assets/[^\s]+)$', pubspec.read_text(), re.M):
        declared = match[1]
        if declared.endswith('/'):
            if declared != 'assets/photos/':
                raise ValueError('Asset directory has no explicit manifest: ' + declared)
            photos = json.loads((root / 'assets/assets/italic/species_photos_v1.json').read_text())
            for photo in photos['photos']:
                asset = photo['asset']
                if not re.fullmatch(r'assets/photos/[a-f0-9]{24}\.webp', asset):
                    raise ValueError('Invalid photo asset: ' + asset)
                paths.add('assets/' + asset)
        else:
            paths.add('assets/' + declared)
    for family in json.loads((root / 'assets/FontManifest.json').read_text()):
        for font in family['fonts']:
            paths.add('assets/' + font['asset'])
    for path in (root / 'assets/shaders').glob('*.frag'):
        if ' ' not in path.name:
            paths.add(path.relative_to(root).as_posix())
    paths.update('icons/' + name for name in (
        'Icon-192.png', 'Icon-512.png', 'Icon-maskable-192.png', 'Icon-maskable-512.png'))
    # CanvasKit requests these through the local fontFallbackBaseUrl. Keep an
    # explicit, checksummed list rather than depending on an external font CDN.
    fallback_manifest = root / 'offline_fonts.json'
    if fallback_manifest.exists():
        paths.add('offline_fonts.json')
        for font in json.loads(fallback_manifest.read_text())['resources']:
            name = font['path']
            if not re.fullmatch(r'fonts/[A-Za-z0-9_./+\-]+', name) or '..' in Path(name).parts:
                raise ValueError('Invalid fallback font path: ' + name)
            if hashlib.sha256((root / name).read_bytes()).hexdigest() != font['sha256']:
                raise ValueError('Fallback font checksum mismatch: ' + name)
            paths.add(name)
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
