"""Read-only estimate: HEAD a deterministic sample, never download photo bodies."""
import concurrent.futures
import datetime
import hashlib
import json
from pathlib import Path
import random
import statistics
import time
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


def main():
    raw = ROOT / 'cache/italic_keys/full-key.json'
    rows = json.loads(raw.read_text())['keyData']
    taxa = json.loads((ROOT / 'assets/italic/italic_checklist.json').read_text())['taxa']
    by_id = {r['italicId']: r for r in taxa}
    photos = {}
    for row in rows:
        if row.get('italicId') and row.get('speciesImage'):
            taxon_id = int(row['italicId'])
            if taxon_id in by_id:
                photos.setdefault(taxon_id, row['speciesImage'])
    population = sorted(photos, key=lambda i: by_id[i]['scientificName'])
    sample = [population[round(i * (len(population) - 1) / 59)] for i in range(60)]

    def inspect(taxon_id):
        result = {'italicId': taxon_id, 'scientificName': by_id[taxon_id]['scientificName']}
        for kind, path in [('original', photos[taxon_id]),
                           ('thumbnail', photos[taxon_id].replace('/images/', '/thumbnails/'))]:
            url = urllib.parse.urljoin('https://italic.units.it/flora/', path)
            request = urllib.request.Request(url, method='HEAD', headers={
                'User-Agent': 'Italicapp-photo-size-audit/1.0 (metadata only)'})
            try:
                with urllib.request.urlopen(request, timeout=15) as response:
                    content_type = response.headers.get('Content-Type', '')
                    length = response.headers.get('Content-Length')
                    result[kind] = {'url': response.url, 'status': response.status,
                                    'contentType': content_type,
                                    'bytes': int(length) if length and content_type.startswith('image/') else None}
            except Exception as error:
                result[kind] = {'url': url, 'error': str(error), 'bytes': None}
            time.sleep(0.15)
        return result

    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        measured = list(pool.map(inspect, sample))
    summaries = {}
    for kind in ('original', 'thumbnail'):
        values = sorted(r[kind]['bytes'] for r in measured if r[kind].get('bytes') is not None)
        if not values:
            summaries[kind] = {'measured': 0}
            continue
        rng = random.Random(20261103)
        means = sorted(statistics.mean(rng.choices(values, k=len(values))) for _ in range(2000))
        summaries[kind] = {
            'measured': len(values), 'meanBytes': statistics.mean(values),
            'medianBytes': statistics.median(values), 'minBytes': min(values),
            'maxBytes': max(values), 'p90Bytes': values[int(.9 * (len(values) - 1))],
            'estimatedAvailableTaxaBytes': statistics.mean(values) * len(photos),
            'estimatedAll3588Bytes': statistics.mean(values) * len(taxa),
            'bootstrapMean95PercentBytes': [means[49], means[1949]],
        }
    report = {
        'generatedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'method': 'Deterministic, alphabetically spread sample of 60 first image references; HTTP HEAD only; no image bodies downloaded; original and existing thumbnail variants.',
        'imageSource': 'https://italic.units.it/?procedure=images',
        'sourceKeySha256': hashlib.sha256(raw.read_bytes()).hexdigest(),
        'taxa': len(taxa), 'availableReferences': len(photos),
        'notCoveredByThisSource': len(taxa) - len(photos),
        'missingReferences': [
            {'italicId': i, 'scientificName': r['scientificName']}
            for i, r in by_id.items() if i not in photos],
        'summaries': summaries, 'sample': measured,
        'notes': ['Coverage is of the cached key, not proof of absence from the full image archive.',
                  'The first key image may not be the current first gallery image or have a documented reusable license.',
                  'Optimized 50/100/150 kB scenarios below are budgets, not measured resized images.',
                  'Before inclusion, select one correctly identified image and record author, source and individual license.'],
        'budgetScenariosBytes': {str(kb) + 'kB': kb * 1000 * len(taxa) for kb in (50, 100, 150)},
        'appAssetsModified': False,
    }
    output = ROOT / 'reports/species_photos'
    output.mkdir(exist_ok=True)
    (output / 'size-estimate.json').write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
    print(json.dumps({k: report[k] for k in ['taxa', 'availableReferences', 'notCoveredByThisSource', 'summaries']}, indent=2))


if __name__ == '__main__':
    main()
