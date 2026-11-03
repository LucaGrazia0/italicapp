"""Package scientific snapshots for the update button. Does not publish anything."""
import argparse
import hashlib
import json
from pathlib import Path

FILES = ['italic_checklist.json', 'italic_genus_keys.json', 'flavoparmelia_key.json',
         'character_matrix_v2.json', 'character_dictionary_v3.json',
         'api_traits_matrix_v2.json', 'general_reconstructed_key_v1.json',
         'physcia_reconstructed_key_v1.json']


def prepare(root, output, revision, version, release_url, app_build=19):
    if not release_url.startswith('https://github.com/LucaGrazia0/italicapp/releases/download/'):
        raise ValueError('Specificare l’indirizzo della release GitHub del progetto.')
    files = {}
    for name in FILES:
        text = (root / 'assets/italic' / name).read_text()
        json.loads(text)
        files['assets/italic/' + name] = text
    payload = json.dumps({'schemaVersion': 1, 'revision': revision, 'files': files}, ensure_ascii=False).encode()
    if len(payload) > 70 * 1024 * 1024:
        raise ValueError('Il pacchetto supera la dimensione supportata.')
    output.mkdir(parents=True, exist_ok=True)
    data_name = 'italicapp-data.json'
    (output / data_name).write_bytes(payload)
    manifest = {'schemaVersion': 1, 'revision': revision, 'version': version,
                'minimumAppBuild': 19, 'appBuild': app_build,
                'dataUrl': release_url.rstrip('/') + '/' + data_name,
                'apkUrl': release_url.rstrip('/') + f'/Italicapp-{version}-Android.apk',
                'bytes': len(payload), 'sha256': hashlib.sha256(payload).hexdigest()}
    (output / 'italicapp-data-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'Pacchetto pronto: {len(payload)/1024/1024:.1f} MB; {len(files)} archivi; nessuna pubblicazione eseguita.')
    return manifest


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    p.add_argument('--output', type=Path, default=Path('dist/data-update'))
    p.add_argument('--revision', type=int, required=True)
    p.add_argument('--version', required=True)
    p.add_argument('--release-url', required=True)
    args = p.parse_args()
    prepare(args.root, args.output, args.revision, args.version, args.release_url)
