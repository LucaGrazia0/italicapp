#!/usr/bin/env python3
"""Build a traceable, sparse taxon × character matrix without executing SQL.

Structured source codes are transcribed. Description patterns only produce
review candidates: they never become validated diagnostic characters.
Omitted cells mean unknown, never absent. Generation is deterministic.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re

from import_italic_ecology import GROWTH, PHOTOBIONTS, REPRODUCTION, SUBSTRATES

ROOT = Path(__file__).resolve().parents[1]
VERSION = 'character-matrix-v1'
BINARY = {'present': 'Presente', 'absent': 'Assenza esplicita'}
REAGENTS = ['K', 'C', 'KC', 'P', 'UV']
COMPARTMENTS = {'thallus': 'Tallo', 'upper_cortex': 'Corteccia superiore', 'medulla': 'Medulla'}
DICTIONARY = json.loads((ROOT / 'assets/italic/character_dictionary_v3.json').read_text())
def dictionary_pattern(terms):
    if not terms or any(not isinstance(t, str) or not t.strip() for t in terms):
        raise ValueError('Invalid dictionary terms')
    return '(?:' + '|'.join(re.escape(t) for t in terms) + ')'

FEATURES = {entry['id']: (entry['label'], dictionary_pattern(entry['matrixTerms']))
            for entry in DICTIONARY['characters'] if 'matrixTerms' in entry}
SORALIA_WORD = dictionary_pattern(next(e for e in DICTIONARY['characters'] if e['id'] == 'soredia')['matrixImpliedTerms'])
SCOPE = re.compile(r'\b(upper cortex|lower cortex|cortex|medulla|thallus|apothecia|hymenium|epithecium|hypothecium|exciple|soralia|soredia|isidia)\b', re.I)


def definitions():
    out = []
    for identifier, label, options in [
        ('growthForm', 'Forma di crescita / tipo biologico', GROWTH),
        ('photobiont', 'Fotobionte', PHOTOBIONTS),
        ('reproductiveStrategy', 'Strategia riproduttiva prevalente', REPRODUCTION),
        ('substrata', 'Substrati documentati', SUBSTRATES),
    ]:
        out.append({'id': identifier, 'label': label, 'group': 'Dati strutturati',
                    'states': options, 'description': 'Codice originale ITALIC. Una strategia prevalente non documenta l’assenza di altre strutture.'})
    for identifier, (label, _) in FEATURES.items():
        out.append({'id': identifier, 'label': label, 'group': 'Morfologia',
                    'states': BINARY, 'description': 'Estrazione testuale conservativa da revisionare. Variabilità e conflitti restano da chiarire.'})
    for compartment, label in COMPARTMENTS.items():
        for reagent in REAGENTS:
            out.append({'id': f'{compartment}_{reagent}', 'label': f'{label} · {reagent}',
                        'group': 'Chimica', 'states': {'positive': '+', 'negative': '−'},
                        'description': 'Segno della reazione riportata per questo compartimento. Colore, sequenza e condizioni restano nella citazione; estrazione da revisionare.'})
    out.extend([
        {'id': 'pilot_soredia', 'label': 'Flavoparmelia · aspetto dei soredi', 'group': 'Pilota',
         'states': {'granular_pustulate': 'Granulari / pustulati', 'farinose': 'Farinosi'},
         'description': 'Codifica manuale del prototipo per i soli taxa 978 e 979; richiede revisione specialistica.'},
        {'id': 'pilot_medulla_K', 'label': 'Flavoparmelia · colore K medulla', 'group': 'Pilota',
         'states': {'dirty_yellow': 'Giallo sporco', 'yellow_red': 'Giallo → rosso / rosso-bruno'},
         'description': 'Reazione della medulla del prototipo; non si applica alla corteccia. Richiede revisione specialistica.'},
    ])
    return out


def evidence(field, quote, rule, start=None, end=None):
    item = {'field': field, 'quote': quote, 'rule': rule}
    if start is not None:
        item.update(start=start, end=end)
    return item


def cell(values, proofs, review='needs_review', ambiguous=False):
    return {'status': 'ambiguous' if ambiguous else 'recorded',
            'values': sorted(set(values)), 'review': review, 'evidence': proofs}


def soralia_observations(description):
    """Documented soralia imply soredia; their absence does not imply the reverse."""
    observations = []
    word = SORALIA_WORD
    for match in re.finditer(r'[^.;]+(?:[.;]|$)', description):
        raw = match.group(); quote = raw.strip()
        if not re.search(rf'\b{word}\b', quote, re.I):
            continue
        negative = bool(re.search(
            rf'\b(?:without|lacking|no|not)\b[^.;]{{0,100}}\b{word}\b|\b{word}\s+(?:(?:are|is)\s+)?(?:absent|lacking)\b', quote, re.I))
        comparison = bool(re.search(
            rf'\b(?:resembl\w*|similar|unlike|compar\w*|differs|differing|other species|other taxa|as in)\b|\b{word}[- ]like\b', quote, re.I))
        positive = not (negative or comparison) and bool(re.search(
            rf'^\s*{word}\b|\bwith\b[^.;]{{0,120}}\b{word}\b', quote, re.I))
        uncertain = bool(re.search(
            r'\b(?:rare(?:ly)?|sometimes|occasionally|when|except|otherwise|or|may|can)\b', quote, re.I))
        start = match.start() + len(raw) - len(raw.lstrip())
        observations.append(('present' if positive else None,
                             uncertain or not positive,
                             evidence('description', quote, 'morphology-soredia-from-soralia-v1', start, start + len(quote))))
    return observations


def morphology(description):
    result = {}
    for identifier, (_, word) in FEATURES.items():
        observations = []
        for match in re.finditer(r'[^.;]+(?:[.;]|$)', description):
            raw = match.group(); quote = raw.strip()
            if not re.search(rf'\b{word}\b', quote, re.I):
                continue
            start = match.start() + len(raw) - len(raw.lstrip())
            negative = bool(re.search(
                rf'\b(?:without|lacking|no)\s+(?:(?:any|true)\s+)?{word}\b|\b{word}\s+(?:(?:are|is)\s+)?(?:absent|lacking)\b', quote, re.I))
            # A word mention alone is not proof of presence. E.g. "soredia-like"
            # or a comparison with another taxon remains an unresolved mention.
            positive = not negative and bool(re.search(
                rf'^\s*{word}\b(?![- ]like)|\bwith\b[^.;]{{0,120}}\b{word}\b(?![- ]like)', quote, re.I))
            uncertain = bool(re.search(r'\b(?:rare(?:ly)?|sometimes|occasionally|when|except|otherwise|or)\b', quote, re.I))
            value = 'absent' if negative else 'present' if positive else None
            rule = f'morphology-{identifier}-v2' if identifier == 'cilia' else f'morphology-{identifier}-v1'
            observations.append((value, uncertain or value is None,
                                 evidence('description', quote, rule, start, start + len(quote))))
        if identifier == 'soredia':
            soralia = soralia_observations(description)
            # A negative/neutral soralia mention cannot cancel directly
            # documented diffuse soredia, nor create a soredia absence.
            observations.extend(soralia if not observations else
                                [o for o in soralia if o[0] is not None])
        if observations:
            values = [v for v, _, _ in observations if v]
            result[identifier] = cell(values, [e for _, _, e in observations],
                                      ambiguous=len(set(values)) != 1 or any(u for _, u, _ in observations))
    return result


def chemistry(description):
    result = {}
    section = re.search(r'\bSpot tests?:\s*(.*?)(?=\bChemistry:|$)', description, re.I | re.S)
    if not section:
        return result
    body = section.group(1)
    markers = list(SCOPE.finditer(body))
    for i, marker in enumerate(markers):
        scope = marker.group().lower().replace(' ', '_')
        if scope not in COMPARTMENTS:
            continue
        end = markers[i + 1].start() if i + 1 < len(markers) else len(body)
        # Never carry the scope across a semicolon or sentence boundary.
        end = min(end, next((m.start() for m in re.finditer(r'[;.]', body[marker.start():end])), end - marker.start()) + marker.start())
        raw = body[marker.start():end]
        quote = raw.strip(' ,;\n')
        if not quote:
            continue
        start = section.start(1) + marker.start()
        for reagent in REAGENTS:
            tokens = re.findall(rf'(?<![A-Za-z/]){reagent}\s*([+−-])(?!/)', quote)
            if not tokens:
                continue
            values = ['positive' if t == '+' else 'negative' for t in tokens]
            identifier = f'{scope}_{reagent}'
            proof = evidence('description', quote, f'spot-{scope}-{reagent}-v1', start, start + len(quote))
            uncertain = len(set(values)) > 1 or bool(re.search(r'\b(?:or|sometimes|rarely|occasionally|faint|weak|slow|often)\w*\b', quote, re.I))
            if identifier in result:
                old = result[identifier]
                values += old['values']
                proofs = old['evidence'] + [proof]
                uncertain = uncertain or old['status'] == 'ambiguous' or len(set(values)) > 1
            else:
                proofs = [proof]
            result[identifier] = cell(values, proofs, ambiguous=uncertain)
    return result


def build(snapshot, pilot):
    chars = definitions()
    rows = []
    seen = set()
    for taxon in snapshot['taxa']:
        identifier = taxon['italicId']
        if not isinstance(identifier, int) or identifier in seen:
            raise ValueError('Invalid or duplicate taxon ID')
        seen.add(identifier)
        cells = {}
        codes = taxon.get('ecologyCodes', {})
        for field, options in [('growthForm', GROWTH), ('photobiont', PHOTOBIONTS),
                               ('reproductiveStrategy', REPRODUCTION), ('substrata', SUBSTRATES)]:
            raw = codes.get(field, '')
            values = raw.split('-') if field == 'substrata' and raw else [raw]
            if raw and all(v in options for v in values):
                cells[field] = cell(values, [evidence(f'ecologyCodes.{field}', raw, 'structured-code-v1')], 'structured_source')
        description = taxon.get('description') or ''
        cells.update(morphology(description))
        cells.update(chemistry(description))
        # Preserve the original limited scope and evidence of the existing pilot.
        if identifier in pilot['covered_taxa'] and taxon['scientificName'].split()[0] == pilot['genus']:
            for question in pilot['questions']:
                quote = question['evidence'].get(str(identifier))
                if not quote or quote not in description:
                    continue
                question_id = question['id']
                state = question['states'][str(identifier)]
                values = {'soredia': {'a': 'granular_pustulate', 'b': 'farinose'},
                          'medulla_k': {'a': 'dirty_yellow', 'b': 'yellow_red'}}
                output_id = {'soredia': 'pilot_soredia', 'medulla_k': 'pilot_medulla_K'}
                start = description.index(quote)
                cells[output_id[question_id]] = cell([values[question_id][state]],
                    [evidence('description', quote, f'curated-{pilot["id"]}-{question_id}', start, start + len(quote))], 'needs_expert_review')
        rows.append({'italicId': identifier, 'scientificName': taxon['scientificName'], 'cells': cells})
    rows.sort(key=lambda row: (row['scientificName'].lower(), row['italicId']))
    return {'schemaVersion': 1, 'metadata': {'builder': VERSION,
            'unknown_semantics': 'An omitted cell is unknown, never absent.',
            'review_policy': 'Description extractions and the curated pilot require expert review. Only the four structured columns feed the preliminary guided key; no extraction feeds automatic exclusion.'},
            'characters': chars, 'taxa': rows}


def validate(matrix, snapshot):
    source = {t['italicId']: t for t in snapshot['taxa']}
    chars = {c['id']: c for c in matrix['characters']}
    if len(source) != len(matrix['taxa']):
        raise ValueError('Taxon count mismatch')
    for row in matrix['taxa']:
        taxon = source[row['italicId']]
        if row['scientificName'] != taxon['scientificName']:
            raise ValueError('Name mismatch')
        for key, entry in row['cells'].items():
            if key not in chars or not set(entry['values']) <= set(chars[key]['states']):
                raise ValueError('Unknown character or state')
            if not entry['evidence'] or (entry['status'] == 'recorded' and not entry['values']):
                raise ValueError('A recorded state must have values and evidence')
            for proof in entry['evidence']:
                value = taxon
                for part in proof['field'].split('.'):
                    value = value.get(part) if isinstance(value, dict) else None
                if not isinstance(value, str) or proof['quote'] not in value:
                    raise ValueError('Evidence not present in source')
                if 'start' in proof and value[proof['start']:proof['end']] != proof['quote']:
                    raise ValueError('Evidence offset mismatch')


def report(matrix):
    total = len(matrix['taxa'])
    out = ['# Matrice taxa × caratteri — prima versione', '',
           f'{total} taxa (incluse entità infraspecifiche) × {len(matrix["characters"])} caratteri.', '',
           'Le celle non codificate sono sconosciute, non assenze. Le estrazioni testuali',
           'sono proposte da revisionare; solo i quattro gruppi strutturati alimentano il percorso preliminare.', '',
           '| Carattere | Registrati | Da chiarire | Mancanti |', '|---|---:|---:|---:|']
    reviews = Counter()
    for char in matrix['characters']:
        entries = [row['cells'][char['id']] for row in matrix['taxa'] if char['id'] in row['cells']]
        counts = Counter(e['status'] for e in entries)
        reviews.update(e['review'] for e in entries)
        out.append(f'| {char["label"]} | {counts["recorded"]} | {counts["ambiguous"]} | {total - len(entries)} |')
    out.extend(['', '## Provenienza e revisione', '', *[f'- `{k}`: {v} celle.' for k, v in sorted(reviews.items())], '',
                'Ogni cella disponibile conserva campo sorgente, citazione esatta e regola di estrazione.',
                'Le citazioni dalle descrizioni hanno anche gli offset di inizio e fine.',
                'I segni chimici sono separati per compartimento: tallo, corteccia superiore e medulla.',
                'La corteccia non specificata e le reazioni K/I non vengono attribuite alla corteccia superiore.',
                'Colori e sequenze chimiche non sono ridotti a un segno: rimangono nella citazione da leggere.', '',
                '## Limiti', '',
                '- «Registrato» significa codificato, non validato da un esperto.',
                '- Le regole testuali non risolvono tassonomia, confronti, variabilità o tutte le negazioni.',
                '- Le menzioni senza una presenza/assenza chiaramente codificabile restano «Da chiarire».',
                '- Soralia/soralium documentati propongono soredi presenti, con la citazione originale; negazioni, confronti e condizioni restano da chiarire. L’assenza dei sorali non implica l’assenza dei soredi.',
                '- I termini supportati dalla matrice sono configurati in assets/italic/character_dictionary_v3.json; forme e tipi aggiuntivi sono disponibili come aiuto alla revisione nel dizionario.',
                '- I dati strutturati restano nelle loro categorie: la strategia riproduttiva non diventa assenza di soredi o isidi.',
                '- Le due colonne del pilota riguardano solo i due taxa già coperti dal prototipo.',
                '- Non sono importate tabelle account, foto, cronologie, note personali o il dump SQL.', ''])
    return '\n'.join(out)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--snapshot', type=Path, default=ROOT / 'assets/italic/italic_checklist.json')
    parser.add_argument('--pilot', type=Path, default=ROOT / 'assets/italic/flavoparmelia_key.json')
    parser.add_argument('--output', type=Path, default=ROOT / 'assets/italic/character_matrix_v2.json')
    parser.add_argument('--report', type=Path, default=ROOT / 'reports/character_matrix.md')
    args = parser.parse_args()
    snapshot = json.loads(args.snapshot.read_text())
    matrix = build(snapshot, json.loads(args.pilot.read_text()))
    matrix['metadata'].update(source_sha256=hashlib.sha256(args.snapshot.read_bytes()).hexdigest(),
                              pilot_sha256=hashlib.sha256(args.pilot.read_bytes()).hexdigest())
    validate(matrix, snapshot)
    args.output.write_text(json.dumps(matrix, ensure_ascii=False, separators=(',', ':')) + '\n')
    args.report.write_text(report(matrix))
    print(f'Built {len(matrix["taxa"])} taxa × {len(matrix["characters"])} characters; {sum(len(t["cells"]) for t in matrix["taxa"])} evidence cells')


if __name__ == '__main__':
    main()
