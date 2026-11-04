"""Download this repository's iPhone artifact with bounded authenticated access.

Only GitHub's API receives the credential; range downloads use its HTTPS redirect.
Each completed part is retained for a retry. IPA and archive hashes are verified.
"""
import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path
import shutil
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from github_ios_ci import request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--artifact', required=True, type=int)
    parser.add_argument('--destination', required=True, type=Path)
    parser.add_argument('--version', default='0.8.12')
    args = parser.parse_args()
    metadata = request(f'actions/artifacts/{args.artifact}')
    if metadata.get('expired'):
        raise ValueError('Artifact expired.')
    total = metadata['size_in_bytes']
    digest = metadata.get('digest', '').removeprefix('sha256:')
    try:
        request(f'actions/artifacts/{args.artifact}/zip', redirect=False)
        raise ValueError('Expected authenticated artifact redirect.')
    except urllib.error.HTTPError as response:
        if response.code != 302:
            raise
        url = response.headers['Location']
    if urllib.parse.urlparse(url).scheme != 'https':
        raise ValueError('Invalid download URL.')
    folder = args.destination
    folder.mkdir(parents=True, exist_ok=True)
    parts = folder / f'artifact-{args.artifact}-parts'
    parts.mkdir(exist_ok=True)
    chunk_size = 8 * 1024 * 1024
    bounds = [(start, min(start + chunk_size, total) - 1) for start in range(0, total, chunk_size)]

    def download(pair):
        start, end = pair
        part = parts / str(start)
        if part.exists() and part.stat().st_size == end - start + 1:
            return part
        for attempt in range(3):
            try:
                req = urllib.request.Request(url, headers={'Range': f'bytes={start}-{end}'})
                with urllib.request.urlopen(req, timeout=90) as response:
                    if response.status != 206 or response.headers.get('Content-Range') != f'bytes {start}-{end}/{total}':
                        raise ValueError('Unexpected artifact range response.')
                    with part.open('wb') as output:
                        shutil.copyfileobj(response, output)
                if part.stat().st_size != end - start + 1:
                    raise ValueError('Incomplete download.')
                print(f'Completed {start}-{end} of {total}', flush=True)
                return part
            except Exception:
                if attempt == 2:
                    raise
                time.sleep(1)
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        downloaded = list(pool.map(download, bounds))
    archive_path = folder / 'github-ios-artifact.zip'
    checksum = hashlib.sha256()
    with archive_path.open('wb') as output:
        for part in downloaded:
            with part.open('rb') as source:
                while True:
                    data = source.read(1024 * 1024)
                    if not data:
                        break
                    checksum.update(data)
                    output.write(data)
    if archive_path.stat().st_size != total or (digest and checksum.hexdigest() != digest):
        raise ValueError('Artifact download checksum mismatch.')
    filename = f'Italic-Go-{args.version}-iPhone-non-firmata.ipa'
    allowed = {filename, filename + '.json', filename + '.sha256'}
    with zipfile.ZipFile(archive_path) as archive:
        if set(archive.namelist()) != allowed:
            raise ValueError('Unexpected artifact members.')
        for name in archive.namelist():
            with archive.open(name) as source, (folder / name).open('wb') as output:
                shutil.copyfileobj(source, output)
    ipa = folder / filename
    report = json.loads(ipa.with_suffix('.ipa.json').read_text())
    if hashlib.sha256(ipa.read_bytes()).hexdigest() != report['sha256']:
        raise ValueError('IPA download checksum mismatch.')
    print(json.dumps(report, indent=2), flush=True)


if __name__ == '__main__':
    main()
