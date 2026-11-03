#!/usr/bin/env python3
"""Build an isolated, traceable API traits pilot; never edits app/review data.

Default: 22 Physcia plus Xanthoria, Flavoparmelia and two Absconditella.
--all explicitly requests all local taxa. Cached responses make runs resumable.
Each binary column denotes one API character state, not a complete organ.
Two positive-only indications are added from local structured reproduction data.
"""
import argparse
import copy
from datetime import datetime, timezone
import hashlib
import html
import json
from pathlib import Path
import re
import time
import unicodedata
import urllib.error
import urllib.request
from import_italic_ecology import REPRODUCTION

ROOT = Path(__file__).resolve().parents[1]
BASE = 'https://italic.units.it/api/v2'
META = {'scientific_name', 'data_about', 'warnings'}
LABELS = {
    'growth_form_fruticose': 'Tallo fruticoso',
    'growth_form_foliose': 'Tallo foglioso',
    'growth_form_squamulose': 'Tallo squamuloso',
    'growth_form_leprose': 'Tallo leproso',
    'growth_form_crustose': 'Tallo crostoso',
    'growth_form_lichenicolous': 'Lichenicolo (campo API growth_form)',
    'photobiont_cyanobacterial': 'Fotobionte cianobatterico',
    'photobiont_trentepohlioid': 'Fotobionte trentepohlioide',
    'photobiont_chlorococcoid': 'Fotobionte clorococcoide',
    'photobiont_absent': 'Fotobionte assente',
    'ascocarps_present': 'Ascocarpi presenti',
    'ascocarps_perithecioid': 'Ascocarpi peritecioidi',
    'ascocarps_apothecioid': 'Ascocarpi apotecioidi',
    'apothecia_lecanorine': 'Apoteci lecanorini',
    'apothecia_lirelliform': 'Apoteci lirelliformi',
    'ascospores_pigmented': 'Ascospore pigmentate',
    'ascospores_hyaline': 'Ascospore ialine',
    'ascospores_1-celled': 'Ascospore unicellulari',
    'ascospores_2-celled': 'Ascospore bicellulari',
    'ascospores_more_than_2-celled': 'Ascospore con più di due cellule',
    'ascospores_polarilocular': 'Ascospore polariloculari',
    'ascospores_muriform_or_submuriform': 'Ascospore muriformi / submuriformi',
    'ascospores_less_than_8_per_ascus': 'Meno di 8 ascospore per asco',
    'ascospores_8_per_ascus': '8 ascospore per asco',
    'ascospores_more_than_8_per_ascus': 'Più di 8 ascospore per asco',
    'cortex_k_negative': 'Corteccia K−',
    'cortex_k_yellow_to_orange': 'Corteccia K+ giallo / arancio',
    'cortex_k_red': 'Corteccia K+ rosso',
    'cortex_k_yellow_turning_to_red': 'Corteccia K+ giallo → rosso',
}
REPRODUCTION_LABELS = {
    'reproduction_soredia_or_similar': 'Riproduzione · soredi o strutture simili',
    'reproduction_isidia_or_similar': 'Riproduzione · isidi o strutture simili',
}


def augment_reproduction(matrix, snapshot):
    """Add positive indications of a strategy, never absences of true organs."""
    result = copy.deepcopy(matrix)
    by_id = {t['italicId']: t for t in snapshot['taxa']}
    imported = snapshot.get('metadata', {}).get('ecology_enrichment', {}).get('imported_at', '')
    result['schemaVersion'] = 2
    result['semantics'] = '29 API states with 1/0/null plus two positive-only local reproductive strategy indications; similar structures included; no manual approval or inferred organ absence'
    result['apiCharacterCount'] = len(LABELS)
    result['supplementalSource'] = {
        'kind': 'local_structured_checklist',
        'asset': 'assets/italic/italic_checklist.json',
        'semanticSha256': hashlib.sha256(json.dumps(snapshot, ensure_ascii=False, sort_keys=True).encode()).hexdigest(),
        'snapshotImportedAt': imported,
        'semantics': 'Positive strategy indications only. Soredia-like and isidia-like structures remain included; all other cases unknown, not absent.',
    }
    result['characters'] += [{'id': k, 'label': v, 'origin': 'local_reproductive_strategy'}
                             for k, v in REPRODUCTION_LABELS.items()]
    for row in result['taxa']:
        taxon = by_id[row['italicId']]
        if taxon['scientificName'] != row['scientificName']:
            raise ValueError('Local reproduction identity differs')
        code = taxon.get('ecologyCodes', {}).get('reproductiveStrategy', '')
        quote = taxon.get('reproductiveStrategy') or ''
        consistent = code in REPRODUCTION and quote == REPRODUCTION[code]
        row['reproductionEvidence'] = {
            'field': 'ecologyCodes.reproductiveStrategy', 'quoteField': 'reproductiveStrategy',
            'code': code, 'quote': quote,
            'sourceUrl': taxon.get('sourceUrl', ''),
            'sourceName': 'Checklist ITALIC locale · ecology1.REPRO',
            'snapshotImportedAt': imported,
            'status': 'documented' if consistent else 'source_mismatch' if code in REPRODUCTION else 'unknown',
        }
        row['cells']['reproduction_soredia_or_similar'] = 1 if consistent and code in {'A.s', 'S-A.s'} else None
        row['cells']['reproduction_isidia_or_similar'] = 1 if consistent and code == 'A.i' else None
    return result


def normalized(name):
    return ' '.join(unicodedata.normalize('NFC', name).split())


def coverage(local, remote):
    by_id = {}
    for row in remote:
        if row['taxon_id'] in by_id:
            raise ValueError('Duplicate API taxon ID')
        by_id[row['taxon_id']] = row
    result = []
    for taxon in local:
        remote_row = by_id.get(taxon['italicId'])
        exact = remote_row and remote_row['scientific_name'] == taxon['scientificName']
        compatible = remote_row and normalized(remote_row['scientific_name']) == normalized(taxon['scientificName'])
        result.append({
            'italicId': taxon['italicId'], 'localName': taxon['scientificName'],
            'apiName': remote_row['scientific_name'] if remote_row else None,
            'identity': 'exact' if exact else 'whitespace_equivalent' if compatible else 'unresolved',
        })
    return result


def normalize_row(taxon, payload):
    if not isinstance(payload, dict) or payload.get('data_about') != 'traits':
        raise ValueError('Unexpected API response, not traits')
    if normalized(payload.get('scientific_name', '')) != normalized(taxon['scientificName']):
        raise ValueError('API identity differs: do not merge taxa')
    cells, issues = {}, []
    for key in LABELS:
        raw = payload.get(key)
        valid = type(raw) is int and raw in (0, 1)
        cells[key] = raw if valid else None
        if key in payload and raw is not None and not valid:
            issues.append({'field': key, 'reason': 'Non-binary API value', 'raw': raw})
    for key in sorted(set(payload) - META - set(LABELS)):
        issues.append({'field': key, 'reason': 'Unmapped new API field', 'raw': payload[key]})
    return {
        'italicId': taxon['italicId'], 'scientificName': taxon['scientificName'],
        'apiName': payload['scientific_name'], 'cells': cells,
        'warnings': payload.get('warnings'), 'schemaIssues': issues,
        'review': 'api_source_unreviewed',
    }


def description_conflicts(taxon, row):
    """Narrow explicit-text checks, only flags; never repairs API values."""
    description = taxon.get('description') or ''
    cells, findings = row['cells'], []
    eight = re.search(r'\bAsci\s+8[- ]spored\b', description, re.I)
    if eight and (cells.get('ascospores_less_than_8_per_ascus') == 1 or
                  cells.get('ascospores_more_than_8_per_ascus') == 1 or
                  cells.get('ascospores_8_per_ascus') == 0):
        findings.append({'field': 'ascospores_per_ascus', 'descriptionQuote': eight.group(),
                         'reason': 'API state differs from explicit local description: compare sources'})
    yellow = re.search(r'\bSpot tests?:\s*upper cortex\s+K\+\s*yellow(?=\s*\(|\s*,|\s*;)', description, re.I)
    if yellow and (cells.get('cortex_k_red') == 1 or cells.get('cortex_k_yellow_turning_to_red') == 1):
        findings.append({'field': 'cortex_K', 'descriptionQuote': yellow.group(),
                         'reason': 'API red reaction differs from explicit local yellow reaction: compare sources'})
    return findings


class Client:
    def __init__(self, directory, interval=1.5, offline=False):
        # Current official OpenAPI: 50 requests / 10 seconds. Keep a margin.
        self.directory, self.interval, self.offline = directory, max(0.25, interval), offline
        self.last_request = 0
        directory.mkdir(parents=True, exist_ok=True)

    def get(self, endpoint, filename):
        path = self.directory / filename
        if path.exists():
            record = json.loads(path.read_text())
            if record['url'] != BASE + endpoint:
                raise ValueError('Cached source URL differs')
            return record
        if self.offline:
            raise ValueError(f'Missing cached response: {filename}')
        for attempt in range(3):
            time.sleep(max(0, self.interval - (time.monotonic() - self.last_request)))
            self.last_request = time.monotonic()
            request = urllib.request.Request(BASE + endpoint, headers={
                'Accept': 'application/json', 'User-Agent': 'Italicapp-traits-pilot/1.0'})
            try:
                with urllib.request.urlopen(request, timeout=45) as response:
                    raw = response.read()
                    record = {'url': request.full_url,
                              'retrievedAt': datetime.now(timezone.utc).isoformat(),
                              'httpStatus': response.status,
                              'sha256': hashlib.sha256(raw).hexdigest(),
                              'payload': json.loads(raw)}
                path.write_text(json.dumps(record, ensure_ascii=False, indent=2) + '\n')
                return record
            except urllib.error.HTTPError as error:
                if attempt == 2 or (error.code != 429 and error.code < 500):
                    raise
                retry = error.headers.get('Retry-After', '')
                time.sleep(max(5 * (attempt + 1), float(retry) if retry.isdigit() else 0))
            except (urllib.error.URLError, TimeoutError):
                if attempt == 2:
                    raise
                time.sleep(5 * (attempt + 1))


def render_html(matrix, report, path):
    columns = matrix['characters']
    headers = ''.join(f'<th title="{html.escape(c["id"])}">{html.escape(c["label"])}</th>' for c in columns)
    rows = []
    for row in matrix['taxa']:
        values = ''.join(f'<td>{"?" if row["cells"][c["id"]] is None else row["cells"][c["id"]]}</td>' for c in columns)
        issues = len(row.get('descriptionConflicts', [])) + len(row['schemaIssues']) + bool(row.get('warnings'))
        rows.append(f'<tr><th>{html.escape(row["scientificName"])}<small>ID {row["italicId"]} · {issues} confronti</small></th>{values}</tr>')
    document = '''<!doctype html><html lang="it"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Matrice dei traits · ITALIC API</title><style>
body{font:15px system-ui;margin:24px;background:#f5f3ea;color:#263e32}h1{font-size:26px}
p{max-width:950px;line-height:1.5}.notice{padding:16px;background:#fff3cd;border-radius:12px}
input{padding:12px;width:min(90%,500px);margin:10px 0}.table{overflow:auto;max-height:65vh;background:white}
table{border-collapse:collapse}th,td{padding:10px;border:1px solid #dce3dc;min-width:100px;text-align:center}
thead th{position:sticky;top:0;background:#e5eee4;z-index:2}tbody th{position:sticky;left:0;background:#f0f4ee;min-width:260px;text-align:left}
small{display:block;font-weight:normal;margin-top:6px}a{color:#23583e}</style>
<h1>Matrice dei traits · ITALIC API</h1><p>__SUMMARY__</p>
<p class="notice">Valori trascritti dall’API: <b>1</b> = stato selezionato, <b>0</b> = stato non selezionato nella fonte, <b>?</b> = dato mancante o non interpretabile.
Ogni colonna è uno stato specifico: «apoteci non lecanorini» non significa «apoteci assenti».
Le segnalazioni richiedono confronto con le descrizioni. Nessuna revisione dell’app è stata modificata.</p>
<p>Le due colonne Riproduzione provengono dalla checklist ITALIC locale: 1 indica una strategia documentata tramite soredi o simili, oppure isidi o simili. Gli altri casi restano ?. Non sono conferme di soredi veri o isidi veri; una strategia sessuale non dimostra assenze.</p>
<p>Fonte: <a href="https://italic.units.it/?procedure=api">ITALIC API</a> ·
<a href="matrix.json">Matrice JSON</a> · <a href="coverage.json">Copertura dei 3.588 taxa</a></p>
<details><summary>Confronti con le descrizioni locali</summary>__CONFLICTS__</details>
<label>Cerca specie o ID<br><input id="search" placeholder="Physcia, Xanthoria, 1717…"></label>
<div class="table"><table><thead><tr><th>Taxon</th>__HEADERS__</tr></thead><tbody>__ROWS__</tbody></table></div>
<script>document.getElementById('search').addEventListener('input',function(){const q=this.value.toLowerCase();document.querySelectorAll('tbody tr').forEach(r=>r.hidden=!r.querySelector('th').textContent.toLowerCase().includes(q))});</script></html>'''
    populated = sum(any(v is not None for v in row['cells'].values()) for row in matrix['taxa'])
    summary = f'{len(matrix["taxa"])} / {matrix["requestedTaxa"]} taxa acquisiti × {len(columns)} stati. {populated} taxa con valori disponibili. Identità riconciliata per {report["matched"]}/{report["localTotal"]} taxa locali. I dati sono trascritti dalla fonte e restano da verificare.'
    conflicts = ''.join('<li>' + html.escape(row['scientificName']) + ': ' +
                        '; '.join(html.escape(item['field'] + ' · ' + item['descriptionQuote'])
                                  for item in row['descriptionConflicts']) + '</li>'
                        for row in matrix['taxa'] if row['descriptionConflicts'])
    warnings = ''.join('<li>' + html.escape(row['scientificName']) + ': ' + html.escape(str(row['warnings'])) + '</li>'
                       for row in matrix['taxa'] if row.get('warnings'))
    path.write_text(document.replace('__SUMMARY__', summary).replace('__HEADERS__', headers)
                   .replace('__ROWS__', ''.join(rows)).replace('__CONFLICTS__', '<ul>' + conflicts + warnings + '</ul>'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--all', action='store_true')
    parser.add_argument('--offline', action='store_true')
    parser.add_argument('--interval', type=float, default=1.5,
                        help='Seconds between requests, minimum 0.25 (official limit: 50/10s)')
    parser.add_argument('--output', type=Path, default=ROOT / 'reports/italic_api_traits')
    parser.add_argument('--write-app-asset', action='store_true', help='Write the separate app asset only for a complete, error-free collection')
    args = parser.parse_args()
    output = args.output
    output.mkdir(parents=True, exist_ok=True)
    client = Client(output / 'raw', interval=args.interval, offline=args.offline)
    snapshot = json.loads((ROOT / 'assets/italic/italic_checklist.json').read_text())
    local = snapshot['taxa']
    remote = client.get('/taxa-search', 'all_taxa.json')['payload']['taxa']
    identities = coverage(local, remote)
    report = {'localTotal': len(local), 'apiTotal': len(remote),
              'matched': sum(r['identity'] != 'unresolved' for r in identities),
              'identityOnly': True, 'taxa': identities}
    (output / 'coverage.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    candidates = local if args.all else [t for t in local if t['scientificName'].startswith('Physcia ') or t['italicId'] in {1, 3323, 978, 2594}]
    compatible = {r['italicId'] for r in identities if r['identity'] != 'unresolved'}
    rows, errors = [], []
    for index, taxon in enumerate(candidates, 1):
        taxon_id = taxon['italicId']
        try:
            if taxon_id not in compatible:
                raise ValueError('Unresolved identity in complete API list')
            source = client.get(f'/traits-pa/{taxon_id}', f'traits_{taxon_id}.json')
            row = normalize_row(taxon, source['payload'])
            row['source'] = {k: v for k, v in source.items() if k != 'payload'}
            row['descriptionConflicts'] = description_conflicts(taxon, row)
            rows.append(row)
            if index % 25 == 0 or index == len(candidates):
                print(f'{index}/{len(candidates)} · {len(rows)} valid · {len(errors)} errors', flush=True)
        except (ValueError, urllib.error.URLError, TimeoutError) as error:
            errors.append({'italicId': taxon_id, 'error': str(error)})
            print(f'ERROR · ID {taxon_id}: {error}', flush=True)
        if index % 25 == 0 or index == len(candidates):
            progress = {'processed': index, 'requested': len(candidates),
                        'valid': len(rows), 'errors': errors,
                        'updatedAt': datetime.now(timezone.utc).isoformat()}
            progress_path = output / 'progress.json'
            temporary = progress_path.with_suffix('.tmp')
            temporary.write_text(json.dumps(progress, ensure_ascii=False, indent=2) + '\n')
            temporary.replace(progress_path)
    matrix = {'schemaVersion': 1, 'source': 'ITALIC API v2 traits-pa',
              'semantics': 'One column per API state; 1/0/null; no inference across columns or manual approval',
              'requestedTaxa': len(candidates), 'errors': errors,
              'characters': [{'id': k, 'label': v} for k, v in LABELS.items()], 'taxa': rows}
    matrix = augment_reproduction(matrix, snapshot)
    (output / 'matrix.json').write_text(json.dumps(matrix, ensure_ascii=False, indent=2) + '\n')
    if args.write_app_asset:
        if not args.all or errors or len(rows) != len(local):
            raise ValueError('Incomplete collection cannot replace the app asset')
        target = ROOT / 'assets/italic/api_traits_matrix_v2.json'
        temporary = target.with_suffix('.tmp')
        temporary.write_text(json.dumps(matrix, ensure_ascii=False, separators=(',', ':')) + '\n')
        temporary.replace(target)
    render_html(matrix, report, output / 'matrix.html')
    print(json.dumps({'identityCoverage': report['matched'], 'downloaded': len(rows), 'columns': len(matrix['characters']),
                      'errors': len(errors), 'flaggedRows': sum(bool(r['descriptionConflicts']) for r in rows)}), flush=True)


if __name__ == '__main__':
    main()
