#!/usr/bin/env python3
"""Enrich the checklist from three scientific tables; never execute the dump."""
from __future__ import annotations

import argparse
import copy
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
ALLOWED_TABLES = {'ecology1', 'ecology2', 'distribution'}
SCALES = {
    'pH of the substrata': ('PH1', 'PH2', 1, 5),
    'Solar irradiation': ('LIG1', 'LIG2', 1, 5),
    'Aridity': ('ARID1', 'ARID2', 1, 5),
    'Eutrophication': ('EUTRO1', 'EUTRO2', 1, 5),
    'Altitudinal distribution': ('ALT1', 'ALT2', 1, 6),
    'Poleotolerance': ('PF1', 'PF2', 0, 3),
}
BELTS = dict(zip(
    ['A', 'A1', 'B', 'C', 'D', 'E', 'F', 'G', 'H'],
    ['Alpine belt', 'Subalpine belt', 'Oromediterranean belt', 'Montane belt',
     'Submediterranean belt', 'Padanian area', 'Humid submediterranean belt',
     'Humid mediterranean belt', 'Dry mediterranean belt']))
FREQUENCIES = ['absent', 'extremely rare', 'very rare', 'rare', 'rather rare',
               'rather common', 'common', 'very common', 'extremely common']
GROWTH = {
    'Cr': 'Crustose', 'Cr.pl': 'Crustose placodiomorph', 'Cr.end': 'Crustose endolithic',
    'Fol': 'Foliose', 'Fol.b': 'Foliose, broad lobed', 'Fol.n': 'Foliose, narrow lobed',
    'Fol.u': 'Foliose, umbilicate', 'Frut': 'Fruticose', 'Frut.f': 'Fruticose filamentous',
    'Sq': 'Squamulose', 'Lepr': 'Leprose', 'LF': 'Lichenicolous fungus',
    'F': 'Non-lichenised and non-lichenicolous (including semilichens)',
}
PHOTOBIONTS = {
    'Ch': 'green algae other than Trentepohlia', 'Tr': 'Trentepohlia',
    'Cy.h': 'cyanobacteria, filamentous (e.g. Nostoc, Scytonema)',
    'Cy.c': 'cyanobacteria, coccaceous (e.g. Gloeocapsa)',
    'Ch-Cy.h': 'green algae other than Trentepohlia (primary); cyanobacteria, filamentous (secondary, e.g. in cephalodia)',
}
REPRODUCTION = {
    'S': 'mainly sexual',
    'A.s': 'mainly asexual, by soredia, or soredia-like structures (e.g. blastidia)',
    'A.i': 'mainly asexual, by isidia, or isidia-like structures (e.g. schizidia)',
    'A.f': 'mainly asexual, by thallus fragmentation',
    'A.c': 'mainly asexual, by conidia and thalloconidia',
    'S-A.c': 'mainly sexual, or asexual by conidia and thalloconidia',
    'S-A.s': 'mainly sexual, or asexual by soredia, or soredia-like structures (e.g. blastidia)',
}
SUBSTRATES = {'Sax': 'rocks', 'Epiph': 'bark', 'Lign': 'lignum',
              'Terr': 'soil, terricolous mosses, and plant debris', 'Foliic': 'leaves'}


def parse_tuple(text):
    """Decode SQL literals, including escaped quotes, without evaluating SQL."""
    values = []; chars = []; quoted = False; string = False; i = 1
    while i < len(text):
        c = text[i]
        if quoted:
            if c == '\\':
                i += 1
                e = text[i]
                chars.append({'n': '\n', 'r': '\r', 't': '\t', '0': '\0', 'Z': '\x1a'}.get(e, e))
            elif c == "'":
                if i + 1 < len(text) and text[i + 1] == "'":
                    chars.append("'"); i += 1
                else:
                    quoted = False
            else:
                chars.append(c)
        elif c == "'":
            if ''.join(chars).strip():
                raise ValueError('Unexpected text before SQL string')
            chars = []; quoted = True; string = True
        elif c in ',)':
            value = ''.join(chars)
            if not string:
                value = value.strip()
                if value.upper() == 'NULL':
                    value = None
                elif re.fullmatch(r'-?\d+', value):
                    value = int(value)
                else:
                    raise ValueError('Unsupported SQL literal in a scientific table')
            values.append(value); chars = []; string = False
            if c == ')':
                return values
        else:
            if not (string and c.isspace()):
                chars.append(c)
        i += 1
    raise ValueError('Incomplete SQL tuple')


def read_scientific_tables(path):
    tables = {name: {} for name in ALLOWED_TABLES}
    current = None; columns = []; buffer = []; quoted = False; escaped = False
    with Path(path).open(encoding='utf-8') as source:
        for line in source:
            header = re.match(r'^INSERT INTO `([^`]+)` \((.*?)\) VALUES\s*(.*)', line)
            if header:
                if buffer:
                    raise ValueError('Unterminated scientific INSERT')
                current = header[1] if header[1] in ALLOWED_TABLES else None
                columns = re.findall(r'`([^`]+)`', header[2])
                line = header[3]
            if current is None:
                continue
            for char in line:
                if not buffer:
                    if char == '(':
                        buffer = ['(']; quoted = False; escaped = False
                    elif char == ';':
                        current = None; break
                    continue
                buffer.append(char)
                if quoted and escaped:
                    escaped = False
                elif quoted and char == '\\':
                    escaped = True
                elif char == "'":
                    quoted = not quoted
                elif char == ')' and not quoted:
                    values = parse_tuple(''.join(buffer)); buffer = []
                    if len(values) != len(columns):
                        raise ValueError(f'Column count mismatch in {current}')
                    row = dict(zip(columns, values)); taxon_id = row.get('NUM')
                    if not isinstance(taxon_id, int) or taxon_id in tables[current]:
                        raise ValueError(f'Invalid or duplicate NUM in {current}: {taxon_id}')
                    tables[current][taxon_id] = row
    if buffer:
        raise ValueError('Truncated scientific INSERT')
    if not all(tables.values()):
        raise ValueError('The dump must contain ecology1, ecology2 and distribution')
    return tables


def normalized(value):
    return ' '.join((value or '').split())


def enrich(snapshot, tables):
    result = copy.deepcopy(snapshot)
    report = {'matched_taxa': 0, 'preserved_without_sql': [], 'unmatched_sql_ids': [],
              'scales_added': dict.fromkeys(SCALES, 0), 'conflicts': [], 'invalid_ranges': []}
    existing_ids = {taxon['italicId'] for taxon in result['taxa']}
    for taxon in result['taxa']:
        taxon_id = taxon['italicId']; row = tables['ecology1'].get(taxon_id)
        if not row or not normalized(row.get('SP')):
            report['preserved_without_sql'].append(taxon_id); continue
        if normalized(row['SP']) != normalized(taxon['scientificName']):
            report['conflicts'].append({'id': taxon_id, 'field': 'scientificName'}); continue
        report['matched_taxa'] += 1
        codes = {target: normalized(row.get(source)) for target, source in
                 [('growthForm', 'GROWTH'), ('photobiont', 'PHOTO'),
                  ('reproductiveStrategy', 'REPRO'), ('substrata', 'SUBST')]}
        taxon['ecologyCodes'] = codes
        for target, mapping in [('growthForm', GROWTH), ('photobiont', PHOTOBIONTS),
                                ('reproductiveStrategy', REPRODUCTION)]:
            code = codes[target]
            if code:
                if code not in mapping:
                    raise ValueError(f'Unknown {target} code: {code}')
                taxon[target] = mapping[code]
        substrate_codes = codes['substrata'].split('-') if codes['substrata'] else []
        if any(code not in SUBSTRATES for code in substrate_codes):
            raise ValueError(f'Unknown substrate code for {taxon_id}')
        if substrate_codes:
            taxon['substrata'] = '; '.join(SUBSTRATES[c] for c in SUBSTRATES if c in substrate_codes)
        traits = {k: normalized(row.get(k)) for k in ['OC', 'COAST', 'SRW', 'PARAS', 'TAX', 'METAL', 'PION']
                  if normalized(row.get(k))}
        taxon['ecologicalTraits'] = traits
        e2 = tables['ecology2'].get(taxon_id)
        if e2 and normalized(e2.get('SP')) == normalized(taxon['scientificName']):
            scales = taxon.setdefault('ecologicalScales', {})
            for label, (lo, hi, minimum, maximum) in SCALES.items():
                low, high = e2.get(lo), e2.get(hi)
                if low is None or high is None:
                    continue
                if not (isinstance(low, int) and isinstance(high, int) and minimum <= low <= high <= maximum):
                    report['invalid_ranges'].append({'id': taxon_id, 'scale': label}); continue
                value = {'min': low, 'max': high, 'values': list(range(low, high + 1))}
                if label not in scales:
                    scales[label] = value; report['scales_added'][label] += 1
                elif scales[label] != value:
                    report['conflicts'].append({'id': taxon_id, 'field': label})
            belts = taxon.setdefault('belts', {})
            for column, label in BELTS.items():
                frequency = e2.get(column)
                if isinstance(frequency, int) and 0 <= frequency < len(FREQUENCIES):
                    value = FREQUENCIES[frequency]
                    if label not in belts:
                        belts[label] = value
                    elif belts[label] != value:
                        report['conflicts'].append({'id': taxon_id, 'field': label})
        distribution = tables['distribution'].get(taxon_id)
        if distribution and normalized(distribution.get('SP')) == normalized(taxon['scientificName']):
            if not normalized(taxon.get('distribution')) and normalized(distribution.get('REGIONS')):
                taxon['distribution'] = normalized(distribution['REGIONS'])
    report['unmatched_sql_ids'] = sorted(set(tables['ecology1']) - existing_ids)
    report['coverage'] = {label: sum(label in t.get('ecologicalScales', {}) for t in result['taxa']) for label in SCALES}
    return result, report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sql', required=True, type=Path)
    parser.add_argument('--snapshot', type=Path, default=ROOT / 'assets/italic/italic_checklist.json')
    parser.add_argument('--output', type=Path, help='Defaults to updating --snapshot')
    parser.add_argument('--report', type=Path, default=ROOT / 'reports/ecology_import.json')
    args = parser.parse_args()
    original = json.loads(args.snapshot.read_text(encoding='utf-8'))
    tables = read_scientific_tables(args.sql)
    result, report = enrich(original, tables)
    # Integrity issues never overwrite a working scientific snapshot.
    if report['conflicts'] or report['invalid_ranges']:
        raise SystemExit(json.dumps(report, ensure_ascii=False, indent=2))
    digest = hashlib.sha256()
    with args.sql.open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(block)
    metadata = result.setdefault('metadata', {})
    metadata['ecology_enrichment'] = {
        'source': 'ITALIC SQL dump', 'sha256': digest.hexdigest(),
        'tables': sorted(ALLOWED_TABLES), 'matched_taxa': report['matched_taxa'],
        'imported_at': datetime.now(timezone.utc).isoformat(),
    }
    metadata['status'] = 'structured-snapshot-with-sql-ecology-v1'
    output = args.output or args.snapshot
    temporary = output.with_suffix('.json.tmp')
    temporary.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    temporary.replace(output)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
