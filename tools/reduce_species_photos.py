"""Preview/apply a half-byte photo budget, preserving full frames and provenance."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import shutil
import concurrent.futures
import threading
import zipfile
from datetime import datetime, timezone

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
PREVIEW = ROOT / 'reports/species_photos/half-size-preview'


def reduce_photo(data, ratio=.5):
    target = round(len(data) * ratio)
    image = Image.open(io.BytesIO(data)).convert('RGB')
    work = image.copy()
    while True:
        def encode(quality):
            output = io.BytesIO()
            work.save(output, format='WEBP', quality=quality, method=6)
            return output.getvalue()
        minimum = encode(55)
        if len(minimum) <= target or min(work.size) <= 160:
            lo, hi, best, quality = 55, 82, minimum, 55
            while lo <= hi:
                mid = (lo + hi) // 2
                candidate = encode(mid)
                if len(candidate) <= target:
                    best, quality, lo = candidate, mid, mid + 1
                else:
                    hi = mid - 1
            return best, {'width': work.width, 'height': work.height, 'quality': quality,
                          'bytes': len(best), 'previousBytes': len(data),
                          'reductionPercent': (1 - len(best) / len(data)) * 100,
                          'sha256': hashlib.sha256(best).hexdigest()}
        work = image.resize((round(work.width * .95), round(work.height * .95)), Image.Resampling.LANCZOS)


def preview(catalogue):
    PREVIEW.mkdir(parents=True, exist_ok=True)
    font = ImageFont.truetype(str(ROOT / 'assets/fonts/Roboto-Regular.ttf'), 23)
    results = []
    for taxon_id in [3072, 1717, 822]:
        photo = next(p for p in catalogue['photos'] if p['italicId'] == taxon_id)
        data = (ROOT / photo['asset']).read_bytes()
        after, meta = reduce_photo(data)
        before_path = PREVIEW / f'{taxon_id}-prima.webp'
        after_path = PREVIEW / f'{taxon_id}-dopo.webp'
        before_path.write_bytes(data)
        after_path.write_bytes(after)
        original = Image.open(io.BytesIO(data)).convert('RGB')
        compressed = Image.open(io.BytesIO(after)).convert('RGB').resize(original.size, Image.Resampling.LANCZOS)
        w, h = original.size
        sheet = Image.new('RGB', (2 * w + 48, h + 135), '#f5f2e9')
        draw = ImageDraw.Draw(sheet)
        draw.text((16, 10), photo['scientificName'], fill='#234c3a', font=font)
        draw.text((16, 47), f"PRIMA: {len(data)/1000:.1f} kB · {w} × {h}", fill='#27332f', font=font)
        draw.text((w + 32, 47), f"DOPO: {len(after)/1000:.1f} kB · −{meta['reductionPercent']:.1f}%", fill='#27332f', font=font)
        sheet.paste(original, (16, 84))
        sheet.paste(compressed, (w + 32, 84))
        draw.text((16, h + 96), 'Stessa foto e inquadratura. A destra: prova a circa metà peso.', fill='#27332f', font=font)
        sheet.save(PREVIEW / f'{taxon_id}-confronto.png')
        results.append({'italicId': taxon_id, 'scientificName': photo['scientificName'],
                        'asset': photo['asset'], 'credit': photo['credit'], **meta})
    (PREVIEW / 'preview.json').write_text(json.dumps(results, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(results, ensure_ascii=False, indent=2))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--preview', action='store_true')
    parser.add_argument('--apply-approved', action='store_true')
    args = parser.parse_args()
    catalogue = json.loads((ROOT / 'assets/italic/species_photos_v1.json').read_text())
    if args.preview:
        preview(catalogue)
    elif args.apply_approved:
        local = threading.local()
        baseline = ROOT / 'dist/Italicapp-0.8.10-Android.apk'
        def process(photo):
            if not hasattr(local, 'archive'):
                local.archive = zipfile.ZipFile(baseline)
            data = local.archive.read('assets/flutter_assets/' + photo['asset'])
            after, meta = reduce_photo(data)
            target = ROOT / photo['asset']
            temporary = target.with_suffix('.reduce.tmp')
            temporary.write_bytes(after)
            temporary.replace(target)
            return {**photo, **meta, 'profile': 'webp-half-bytes-from-0.8.10-v1'}
        photos = []
        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
            for photo in pool.map(process, catalogue['photos']):
                photos.append(photo)
                if len(photos) % 100 == 0:
                    print('Reduced', len(photos), 'photos', flush=True)
        old_bytes = sum(p['previousBytes'] for p in photos)
        catalogue.update(photos=photos, bytes=sum(p['bytes'] for p in photos),
                         profile='webp-half-bytes-from-0.8.10-v1',
                         generatedAt=datetime.now(timezone.utc).isoformat())
        (ROOT / 'assets/italic/species_photos_v1.json').write_text(json.dumps(catalogue, ensure_ascii=False, indent=2)+'\n')
        report = {'photoTaxa': len(photos), 'previousBytes': old_bytes, 'bytes': catalogue['bytes'],
                  'reductionPercent': (1-catalogue['bytes']/old_bytes)*100,
                  'baseline': str(baseline), 'userApproved': True,
                  'diaryPhotosChanged': False}
        (PREVIEW / 'applied.json').write_text(json.dumps(report, indent=2)+'\n')
        print(json.dumps(report, indent=2), flush=True)
    else:
        raise ValueError('Apply the full catalogue only after the visual preview has been approved.')


if __name__ == '__main__':
    main()
