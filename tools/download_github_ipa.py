"""Resume this build's authenticated artifact with bounded HTTP range requests."""
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import threading
import time
import urllib.error
import urllib.request
import zipfile
from github_ios_ci import request


def main():
    artifact_id = 13278917205
    expected_bytes = 384290938
    expected_hash = '8fb9a99e5b2a2ada26c8564a6199cedf959f1111f00bcfb46c5be0de9a348bb1'
    try:
        request(f'actions/artifacts/{artifact_id}/zip', redirect=False)
        raise ValueError('Expected authenticated artifact redirect.')
    except urllib.error.HTTPError as response:
        if response.code != 302:
            raise
        url = response.headers['Location']
    folder = Path('dist/ios-0.8.10')
    archive_path = folder / 'github-ios-artifact.zip'
    prefix = archive_path.stat().st_size
    if prefix >= expected_bytes:
        raise ValueError('Artifact is not a contiguous partial download.')
    progress = {'completedBytes': prefix, 'totalBytes': expected_bytes, 'logged': prefix}
    lock = threading.Lock()
    descriptor = os.open(archive_path, os.O_RDWR)

    def download(bounds):
        position, end = bounds
        for attempt in range(3):
            try:
                req = urllib.request.Request(url, headers={'Range': f'bytes={position}-{end}'})
                with urllib.request.urlopen(req, timeout=90) as response:
                    if response.status != 206 or response.headers.get('Content-Range') != f'bytes {position}-{end}/{expected_bytes}':
                        raise ValueError('Unexpected artifact range response.')
                    while position <= end:
                        chunk = response.read(min(256 * 1024, end - position + 1))
                        if not chunk:
                            raise ValueError('Incomplete range download.')
                        written = 0
                        while written < len(chunk):
                            written += os.pwrite(descriptor, chunk[written:], position + written)
                        position += len(chunk)
                        with lock:
                            progress['completedBytes'] += len(chunk)
                            if progress['completedBytes'] - progress['logged'] > 16 * 1024 * 1024:
                                progress['logged'] = progress['completedBytes']
                                print(json.dumps(progress), flush=True)
                                (folder / 'download-progress.json').write_text(json.dumps(progress))
                return
            except Exception:
                if attempt == 2:
                    raise
                time.sleep(1)
    remaining = expected_bytes - prefix
    size = (remaining + 7) // 8
    chunks = [(start, min(start + size, expected_bytes) - 1) for start in range(prefix, expected_bytes, size)]
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        list(pool.map(download, chunks))
    os.fsync(descriptor)
    os.close(descriptor)
    assert archive_path.stat().st_size == expected_bytes
    assert hashlib.sha256(archive_path.read_bytes()).hexdigest() == expected_hash
    with zipfile.ZipFile(archive_path) as archive:
        for name in archive.namelist():
            if Path(name).name != name or not name.startswith('Italicapp-0.8.10-iPhone-non-firmata.ipa'):
                raise ValueError('Unexpected artifact member.')
            with archive.open(name) as source, (folder / name).open('wb') as output:
                while True:
                    data = source.read(1024 * 1024)
                    if not data:
                        break
                    output.write(data)
    ipa = folder / 'Italicapp-0.8.10-iPhone-non-firmata.ipa'
    report = json.loads(ipa.with_suffix('.ipa.json').read_text())
    assert hashlib.sha256(ipa.read_bytes()).hexdigest() == report['sha256']
    print(json.dumps(report, indent=2), flush=True)


if __name__ == '__main__':
    main()
