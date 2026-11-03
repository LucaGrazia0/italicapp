"""Package only the verified web app, excluding diaries, APKs and old files.

Run after Flutter's web build and prepare_offline_web.py on that output folder.
The archive can be served by a static HTTPS host at the build's base href.
"""
import argparse
import hashlib
import json
import re
import zipfile
from pathlib import Path


def package(root: Path, destination: Path):
    worker = (root / 'italic_offline_worker.js').read_text()
    match = re.search(r'^const PACK = (\{.*\});$', worker, re.M)
    if not match:
        raise ValueError('Eseguire prima tools/prepare_offline_web.py.')
    pack = json.loads(match[1])
    files = []
    for item in pack['resources']:
        relative = Path(item['path'])
        if relative.is_absolute() or '..' in relative.parts:
            raise ValueError('Percorso non valido nel pacchetto offline.')
        data = (root / relative).read_bytes()
        if hashlib.sha256(data).hexdigest() != item['sha256']:
            raise ValueError('Build modificata dopo la preparazione offline: ' + str(relative))
        files.append((relative.as_posix(), data))
    files.append(('italic_offline_worker.js', worker.encode()))
    destination.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(destination, 'w', zipfile.ZIP_DEFLATED) as archive:
        for name, data in files:
            archive.writestr(name, data)
    digest = hashlib.sha256(destination.read_bytes()).hexdigest()
    destination.with_suffix('.zip.sha256').write_text(digest + '  ' + destination.name + '\n')
    print(f'{destination}: {len(files)} file verificati, SHA-256 {digest}')
    return pack


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('build', type=Path)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    package(args.build, args.destination)
