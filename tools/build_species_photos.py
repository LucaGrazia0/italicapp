"""Build a resumable, ID-bound offline copy of the first DoLichens taxon photo.

No taxon names are guessed from filenames. Source identity and photo order are
checked against each public taxon page. Originals stay in the ignored cache.
"""
import argparse
import concurrent.futures
import hashlib
import http.client
import html
import io
import json
from pathlib import Path
import re
import time
import threading
import unicodedata
import urllib.parse
import urllib.request
from datetime import datetime, timezone

from PIL import Image, ImageCms, ImageOps

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / 'cache/species_photos'
OUT = ROOT / 'assets/photos'
MANIFEST = ROOT / 'assets/italic/species_photos_v1.json'
BASE = 'https://italic.units.it/dolichens/index.php?procedure=taxonpage&num='
PROFILE = 'webp-srgb-max960-q82-min78-v1'
LOCKS = {}
LOCKS_GUARD = threading.Lock()
CONNECTION = threading.local()


def text(markup):
    return ' '.join(html.unescape(re.sub(r'<[^>]*>', ' ', markup)).split())


def identity(name):
    return ' '.join(unicodedata.normalize('NFKC', name).split()).casefold()


def fetch(url, limit):
    uri = urllib.parse.urlparse(url)
    if uri.scheme != 'https' or uri.hostname != 'italic.units.it':
        raise ValueError('Unexpected source')
    target = urllib.parse.quote(uri.path, safe="/%:@-._~!$&'()*+,;=")
    if uri.query:
        target += '?' + uri.query
    for attempt in range(3):
        try:
            connection = getattr(CONNECTION, 'client', None)
            if connection is None:
                connection = http.client.HTTPSConnection('italic.units.it', timeout=30)
                CONNECTION.client = connection
            connection.request('GET', target, headers={
                'User-Agent': 'Italicapp-offline-photo-pilot/0.8.10',
            })
            with connection.getresponse() as response:
                if response.status != 200:
                    raise ValueError('HTTP ' + str(response.status))
                if int(response.getheader('Content-Length', '0')) > limit:
                    raise ValueError('Source exceeds the bounded download size')
                body = response.read(limit + 1)
                if len(body) > limit:
                    raise ValueError('Source exceeds the bounded download size')
                return body
        except Exception as error:
            if getattr(CONNECTION, 'client', None):
                CONNECTION.client.close()
                CONNECTION.client = None
            if attempt == 2 or isinstance(error, ValueError):
                raise
            time.sleep(1 + attempt)


def page_info(taxon):
    taxon_id = taxon['italicId']
    cached = CACHE / f'{taxon_id}.json'
    if cached.exists():
        record = json.loads(cached.read_text())
        if record.get('scientificName') == taxon['scientificName']:
            return record
    page = BASE + str(taxon_id)
    markup = fetch(page, 6 * 1024 * 1024).decode('utf-8')
    title = re.search(r'<title>(.*?)</title>', markup, re.S | re.I)
    source_name = text(title[1]).removesuffix(' | Dolichens') if title else ''
    record = {
        'italicId': taxon_id, 'scientificName': taxon['scientificName'],
        'sourceName': source_name, 'pageUrl': page,
        'checkedAt': datetime.now(timezone.utc).isoformat(),
    }
    # The first species image anchor, excluding all logos, maps and icons.
    photo = re.search(
        r'<a\b[^>]*href=[\"\x27]([^\"\x27]*/species/images/[^\"\x27]+)[\"\x27][^>]*>\s*<img\b[^>]*>',
        markup, re.I,
    )
    if identity(source_name) != identity(taxon['scientificName']):
        record.update(status='identity_mismatch')
    elif photo is None:
        record.update(status='no_photo')
    else:
        source_url = urllib.parse.urljoin(page, html.unescape(photo[1]))
        uri = urllib.parse.urlparse(source_url)
        if uri.scheme != 'https' or uri.hostname != 'italic.units.it' or not uri.path.startswith('/flora/images/species/images/'):
            raise ValueError('Unexpected species image URL')
        # Credits belong to this image, before the next photo or page modals.
        remainder = markup[photo.end():]
        boundary = re.search(r'<a\b[^>]*href=[\"\x27][^\"\x27]*/species/images/|<!--\s*MODALI', remainder, re.I)
        section = remainder[:boundary.start()] if boundary else remainder[:3000]
        credits = [text(c) for c in re.findall(r'<h6\b[^>]*>(.*?)</h6>', section, re.S | re.I)]
        credit = ' '.join(c for c in credits if c)
        record.update(status='available', originalUrl=source_url,
                      credit=credit or 'Crediti non specificati nella scheda di origine.',
                      photoOrder=1)
    cached.write_text(json.dumps(record, ensure_ascii=False) + '\n')
    time.sleep(.08)
    return record


def encode(record):
    photo_hash = hashlib.sha256(record['originalUrl'].encode()).hexdigest()[:24]
    original = CACHE / (photo_hash + '.original')
    asset = OUT / (photo_hash + '.webp')
    meta_path = CACHE / (photo_hash + '.encoded.json')
    if asset.exists() and meta_path.exists():
        meta = json.loads(meta_path.read_text())
        if meta.get('profile') == PROFILE:
            return {**record, **meta}
    if original.exists():
        body = original.read_bytes()
        download_url = record['originalUrl']
    else:
        download_url = record['originalUrl']
        try:
            body = fetch(download_url, 8 * 1024 * 1024)
        except Exception:
            # Same first photo, already reduced by ITALIC; never another image.
            download_url = download_url.replace('/species/images/', '/species/thumbnails/')
            body = fetch(download_url, 8 * 1024 * 1024)
        if download_url == record['originalUrl']:
            original.write_bytes(body)
    with Image.open(io.BytesIO(body)) as source:
        source_size = source.size
        image = ImageOps.exif_transpose(source)
        icc = image.info.get('icc_profile')
        if icc:
            image = ImageCms.profileToProfile(
                image, ImageCms.ImageCmsProfile(io.BytesIO(icc)),
                ImageCms.createProfile('sRGB'), outputMode='RGB',
            )
        else:
            image = image.convert('RGB')
        image.thumbnail((960, 960), Image.Resampling.LANCZOS)
        encoded = io.BytesIO()
        quality = 82
        image.save(encoded, format='WEBP', quality=quality, method=6)
        if encoded.tell() > 140000:
            quality = 78
            encoded = io.BytesIO()
            image.save(encoded, format='WEBP', quality=quality, method=6)
        data = encoded.getvalue()
        # Do not force a smaller byte budget at the expense of fine structures.
        meta = {
            'profile': PROFILE, 'asset': asset.relative_to(ROOT).as_posix(),
            'bytes': len(data), 'originalBytes': len(body),
            'width': image.width, 'height': image.height,
            'originalWidth': source_size[0], 'originalHeight': source_size[1],
            'quality': quality, 'sha256': hashlib.sha256(data).hexdigest(),
            'downloadUrl': download_url,
            'sourceVariant': 'original' if download_url == record['originalUrl'] else 'thumbnail',
        }
    temporary = asset.with_suffix('.tmp')
    temporary.write_bytes(data)
    temporary.replace(asset)
    meta_path.write_text(json.dumps(meta) + '\n')
    return {**record, **meta}


def process(taxon):
    try:
        record = page_info(taxon)
        if record['status'] != 'available':
            return record
        with LOCKS_GUARD:
            lock = LOCKS.setdefault(record['originalUrl'], threading.Lock())
        with lock:
            return encode(record)
    except Exception as error:
        return {'italicId': taxon['italicId'], 'scientificName': taxon['scientificName'],
                'status': 'error', 'error': str(error), 'pageUrl': BASE + str(taxon['italicId'])}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--limit', type=int)
    parser.add_argument('--workers', type=int, default=3)
    args = parser.parse_args()
    CACHE.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    taxa = json.loads((ROOT / 'assets/italic/italic_checklist.json').read_text())['taxa']
    # Ensure the user example and familiar Physcia are verified in a pilot run.
    priority = {3072: 0, 1717: 1, 1718: 2, 1719: 3, 1723: 4, 1735: 5}
    taxa.sort(key=lambda t: (priority.get(t['italicId'], 10), t['scientificName']))
    if args.limit:
        taxa = taxa[:args.limit]
    results = []
    start = time.monotonic()
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = [pool.submit(process, taxon) for taxon in taxa]
        for future in concurrent.futures.as_completed(futures):
            results.append(future.result())
            if len(results) % 50 == 0 or len(results) == len(taxa):
                photos = [r for r in results if 'asset' in r]
                print(json.dumps({'done': len(results), 'total': len(taxa), 'photos': len(photos),
                                  'photoMB': round(sum(r['bytes'] for r in photos) / 1e6, 1),
                                  'errors': sum(r['status'] == 'error' for r in results),
                                  'elapsedSeconds': round(time.monotonic() - start)}), flush=True)
    results.sort(key=lambda r: r['italicId'])
    photos = [r for r in results if 'asset' in r]
    unique = {r['asset']: r for r in photos}
    manifest = {
        'schemaVersion': 1, 'generatedAt': datetime.now(timezone.utc).isoformat(),
        'selection': 'First species photo in each DoLichens taxon page; exact ID and source-name match.',
        'profile': PROFILE, 'taxaChecked': len(taxa), 'photoTaxa': len(photos),
        'uniquePhotos': len(unique), 'bytes': sum(r['bytes'] for r in unique.values()),
        'photos': photos,
        'unavailable': [r for r in results if 'asset' not in r],
    }
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    report = ROOT / 'reports/species_photos/offline-build-0.8.10.json'
    report.write_text(json.dumps({k: v for k, v in manifest.items() if k != 'photos'}, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: v for k, v in manifest.items() if k not in ('photos', 'unavailable')}, indent=2), flush=True)


if __name__ == '__main__':
    main()
