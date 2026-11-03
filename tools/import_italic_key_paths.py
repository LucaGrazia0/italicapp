"""Reconstruct a scoped ITALIC tree, keeping occurrence and source identities.

Reads a cached public full-key response. Labels/bindings are a separate, explicit
Italian adaptation: an unavailable label aborts export instead of guessing.
"""
import argparse
import hashlib
import json
from collections import defaultdict
from pathlib import Path


def reconstruct(full, response, reference, adaptation, source_hash):
    by_id = {}
    duplicates = []
    for row in full['keyData']:
        key = row['leadId']
        if not isinstance(key, int):
            raise ValueError('Invalid lead ID')
        if key in by_id:
            if {k: v for k, v in by_id[key].items() if k != 'speciesImage'} != {k: v for k, v in row.items() if k != 'speciesImage'}:
                raise ValueError(f'Conflicting duplicate lead {key}')
            duplicates.append(key)
        by_id[key] = row
    children = defaultdict(list)
    roots = []
    for row in by_id.values():
        parent = row['parentId']
        if parent is None:
            roots.append(row['leadId'])
        elif parent not in by_id:
            raise ValueError('Missing parent')
        else:
            children[parent].append(row['leadId'])
    if len(roots) != 1 or any(len(cs) != 2 for cs in children.values()):
        raise ValueError('Expected one root and binary couplets')
    records = set(response['records'])
    if not records or not all(isinstance(r, str) for r in records):
        raise ValueError('Expected record strings')
    local = {t['italicId']: t for t in reference if t['scientificName'].split()[0] == adaptation['genus']}
    visited, active = set(), set()
    found_records = set()

    def prune(key):
        if key in active or key in visited:
            raise ValueError('Cycle or repeated edge')
        active.add(key)
        row = by_id[key]
        cs = [v for c in children[key] if (v := prune(c)) is not None]
        active.remove(key)
        visited.add(key)
        selected = row['leadRecordId'] in records
        if selected:
            if cs or children[key]:
                raise ValueError('Selected record must be terminal')
            found_records.add(row['leadRecordId'])
            taxon_id = int(row['italicId'])
            taxon = local.get(taxon_id)
            if taxon is None or taxon['scientificName'] != row['leadSpecies']:
                raise ValueError('Taxon identity or scope mismatch')
            return {'sourceLeadIds': [key], 'taxonId': taxon_id,
                    'scientificName': row['leadSpecies'], 'recordId': row['leadRecordId'], 'children': []}
        if not cs:
            return None
        if len(cs) == 1:
            cs[0]['sourceLeadIds'].insert(0, key)
            return cs[0]
        return {'sourceLeadIds': [key], 'children': cs}

    root = prune(roots[0])
    if len(visited) != len(by_id) or root is None:
        raise ValueError('Disconnected tree or empty selection')
    nodes, paths = [], []
    official_counter = 0

    def emit(node, trail):
        nonlocal official_counter
        identity = 'lead_' + str(node['sourceLeadIds'][-1])
        if not node['children']:
            nodes.append({k: node[k] for k in ['sourceLeadIds', 'taxonId', 'scientificName', 'recordId']} | {'id': identity, 'choices': []})
            paths.append({'taxonId': node['taxonId'], 'occurrenceId': identity, 'steps': trail})
            return identity
        official_counter += 1
        ordinal = official_counter
        choices = []
        for child in node['children']:
            # Retain the OUTER lead after unary pruning, just as the official
            # key does; the destination leaf's text is not the branch label.
            outer = next(i for i in child['sourceLeadIds'] if by_id[i]['leadText'])
            label = adaptation['leads'].get(str(outer))
            if label is None:
                raise ValueError(f'Adaptation missing for lead {outer}')
            target = 'lead_' + str(child['sourceLeadIds'][-1])
            choice = {'target': target, 'sourceLeadId': outer,
                      'sourceLeadIds': child['sourceLeadIds'], **label}
            choices.append(choice)
        nodes.append({'id': identity, 'sourceLeadIds': node['sourceLeadIds'],
                      'officialNode': ordinal, 'choices': choices})
        for child, choice in zip(node['children'], choices):
            emit(child, trail + [{'node': identity, 'target': choice['target']}])
        return identity

    root_id = emit(root, [])
    covered = {p['taxonId'] for p in paths}
    if covered != set(local):
        raise ValueError(f'Incomplete taxon coverage: {set(local) - covered}')
    return {
        'schemaVersion': 1, 'id': adaptation['id'], 'genus': adaptation['genus'],
        'title': adaptation['title'], 'root': root_id,
        'status': 'reconstructed_key_conditions',
        'source': {'fullKeyUrl': 'https://italic.units.it/api/v1/full-key',
                   'keyUrl': response['link'], 'keyId': response['key_id'],
                   'sha256': source_hash, 'accessedOn': adaptation['accessedOn'],
                   'citation': 'Nimis P.L. (2026), The lichens of Italy – An interactive guide; Conti M., Martellos S., Nimis P.L. (2026), ITALIC Keymaker.',
                   'adaptation': 'Sintesi italiana dei caratteri; ordine dei bivi ricostruito dalla fonte. Non è una chiave validata da ITALIC.'},
        'diagnostics': {'duplicateImageVariants': sorted(set(duplicates)),
                        'unavailableRecords': sorted(records - found_records)},
        'taxa': [{'italicId': i, 'scientificName': local[i]['scientificName']} for i in sorted(covered)],
        'nodes': nodes, 'paths': paths,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--full-key', type=Path, default=Path('cache/italic_keys/full-key.json'))
    parser.add_argument('--records', type=Path, default=Path('reports/species_key/physcia-response.json'))
    parser.add_argument('--reference', type=Path, default=Path('assets/italic/italic_checklist.json'))
    parser.add_argument('--adaptation', type=Path, default=Path('tools/data/physcia_key_adaptation.json'))
    parser.add_argument('--output', type=Path, default=Path('assets/italic/physcia_reconstructed_key_v1.json'))
    args = parser.parse_args()
    raw = args.full_key.read_bytes()
    result = reconstruct(json.loads(raw), json.loads(args.records.read_text()),
                         json.loads(args.reference.read_text())['taxa'],
                         json.loads(args.adaptation.read_text()), hashlib.sha256(raw).hexdigest())
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'taxa': len(result['taxa']), 'paths': len(result['paths']),
                      'couplets': sum(bool(n['choices']) for n in result['nodes']),
                      'diagnostics': result['diagnostics']}, ensure_ascii=False))


if __name__ == '__main__':
    main()
