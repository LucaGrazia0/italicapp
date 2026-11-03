"""Build the complete public ITALIC tree without inventing missing branches.

Keeps source wording, occurrence IDs, extra-source taxa and unresolved terminals.
Only whitespace/diacritic variants with the SAME taxon ID are reconciled.
"""
import argparse
from collections import defaultdict
import hashlib
import html
import json
from pathlib import Path
import re
import unicodedata
from urllib.parse import urlparse, parse_qs


def normalized_name(value):
    return ' '.join(''.join(c for c in unicodedata.normalize('NFKD', value)
                           if not unicodedata.combining(c)).split()).casefold()


def plain(value):
    return ' '.join(html.unescape(re.sub(r'</?(?:i|b|em|strong|sup|sub|br)\b[^>]*>', ' ', value or '')).split())


def build(full, reference, associated, source_hash):
    local = {r['italicId']: r for r in reference}
    if len(local) != len(reference):
        raise ValueError('Duplicate reference ID')
    rows, duplicates = {}, []
    for row in full['keyData']:
        key = row['leadId']
        if not isinstance(key, int):
            raise ValueError('Invalid lead identity')
        if key in rows:
            compare = lambda r: {k: v for k, v in r.items() if k != 'speciesImage'}
            if compare(rows[key]) != compare(row):
                raise ValueError('Conflicting duplicate lead')
            duplicates.append(key)
        rows[key] = row
    children = defaultdict(list)
    roots = []
    for key, row in rows.items():
        parent = row['parentId']
        if parent is None:
            roots.append(key)
        elif parent not in rows:
            raise ValueError('Orphan source lead')
        else:
            children[parent].append(key)
    if len(roots) != 1 or any(len(v) != 2 for v in children.values()):
        raise ValueError('Source must have one root and binary branches')
    for cs in children.values():
        cs.sort()  # JS numeric-object order in the official client
    covered, extra, aliases, unresolved, nodes, paths = {}, {}, {}, [], [], []
    seen = set()
    ordinal = 0

    def visit(key, trail):
        nonlocal ordinal
        if key in seen:
            raise ValueError('Cycle or repeated source edge')
        seen.add(key)
        row = rows[key]
        identity = f'lead_{key}'
        source_ordinal = None
        # The official client numbers all non-species nodes, including four
        # currently dangling continuations; do not shift links after them.
        if row.get('leadSpeciesId') is None:
            ordinal += 1
            source_ordinal = ordinal
        cs = children[key]
        node = dict(id=identity, sourceLeadIds=[key], choices=[])
        if source_ordinal is not None:
            node['officialNode'] = source_ordinal
        if cs:
            if row.get('leadSpecies') is not None:
                raise ValueError('Species node cannot have children')
            for child in cs:
                label = plain(rows[child]['leadText'])
                if not label:
                    raise ValueError('Missing branch condition')
                node['choices'].append(dict(target=f'lead_{child}', sourceLeadId=child,
                                            label=label, bindings={}))
        elif row.get('italicId') is not None:
            taxon_id = int(row['italicId'])
            name = row['leadSpecies']
            if not name:
                raise ValueError('Taxon without name')
            if taxon_id in local:
                canonical = local[taxon_id]['scientificName']
                if normalized_name(canonical) != normalized_name(name):
                    raise ValueError(f'Identity conflict for {taxon_id}')
                covered[taxon_id] = canonical
                if canonical != name:
                    aliases[taxon_id] = dict(italicId=taxon_id, localName=canonical,
                                            sourceName=name, resolution='same_id_orthographic_variant')
            else:
                if taxon_id in extra and extra[taxon_id] != name:
                    raise ValueError('Conflicting extra taxon name')
                extra[taxon_id] = name
            node.update(taxonId=taxon_id, scientificName=name, recordId=row.get('leadRecordId'))
            paths.append(dict(taxonId=taxon_id, occurrenceId=identity, nodes=trail))
        else:
            group = row.get('leadSpecies')
            label = group or 'Continuazione non disponibile nella risposta della fonte'
            node['unresolvedLabel'] = label
            node['unresolvedKind'] = 'group' if group else 'missing_continuation'
            unresolved.append(dict(node=identity, label=label, kind=node['unresolvedKind'], legacyTo=row.get('leadTo')))
        nodes.append(node)
        for child in cs:
            visit(child, trail + [dict(node=identity, target=f'lead_{child}')])

    visit(roots[0], [])
    if len(seen) != len(rows):
        raise ValueError('Disconnected source nodes')
    missing = []
    for taxon_id in sorted(set(local)-set(covered)):
        response = associated.get(taxon_id)
        if response is None or response.get('scientific_name') != local[taxon_id]['scientificName'] or not isinstance(response.get('keys'), list):
            raise ValueError(f'Associated key audit missing or changed: {taxon_id}')
        links = []
        for item in response['keys']:
            url = urlparse(item['link'])
            query = parse_qs(url.query)
            if (url.scheme != 'https' or url.hostname not in {'italic.units.it', 'dryades.units.it'}
                    or url.username or url.password or url.port or url.fragment
                    or url.path not in {'/home/index.php', '/flora/index.php'}
                    or query.get('procedure') != ['ext_key_home']
                    or not query.get('key_id', [''])[0].isdigit()
                    or not isinstance(item['title'],str)):
                raise ValueError('Unexpected associated key link')
            links.append(dict(url=item['link'],title=item['title']))
        missing.append(dict(italicId=taxon_id, scientificName=local[taxon_id]['scientificName'],
                            associatedKeys=links, auditUrl=f'https://italic.units.it/api/v2/keys/{taxon_id}'))
    return dict(schemaVersion=1, id='italic-general-reconstructed-v1', genus=None,
                title='Chiave generale ITALIC', root=f'lead_{roots[0]}', status='reconstructed_key_conditions', language='en',
                source=dict(keyId='full', keyUrl='https://italic.units.it/key-maker/full/nodes/1/interactive',
                            fullKeyUrl='https://italic.units.it/api/v1/full-key', sha256=source_hash, accessedOn='2026-11-02',
                            citation='Nimis P.L. (2026), The lichens of Italy – An interactive guide; Conti M., Martellos S., Nimis P.L. (2026), ITALIC Keymaker.'),
                referenceCount=len(reference),
                taxa=[dict(italicId=i, scientificName=name) for i, name in sorted(covered.items())],
                additionalSourceTaxa=[dict(italicId=i, scientificName=name) for i, name in sorted(extra.items())],
                unrepresentedTaxa=missing, identityAliases=list(aliases.values()),
                diagnostics=dict(duplicateImageVariants=sorted(set(duplicates)), unavailableRecords=[], unresolvedTerminals=unresolved),
                nodes=nodes, pathCount=len(paths))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--full-key',type=Path,default=Path('cache/italic_keys/full-key.json'))
    parser.add_argument('--output',type=Path,default=Path('assets/italic/general_reconstructed_key_v1.json'))
    args=parser.parse_args()
    raw=args.full_key.read_bytes()
    reference=json.loads(Path('assets/italic/italic_checklist.json').read_text())['taxa']
    associated={int(p.stem):json.loads(p.read_text()) for p in Path('cache/italic_keys/associated').glob('*.json')}
    result=build(json.loads(raw),reference,associated,hashlib.sha256(raw).hexdigest())
    args.output.write_text(json.dumps(result,ensure_ascii=False,separators=(',',':'))+'\n')
    summary={k:len(result[k]) for k in ['taxa','additionalSourceTaxa','unrepresentedTaxa','identityAliases','nodes']}
    summary['paths']=result['pathCount']
    summary['unresolvedTerminals']=result['diagnostics']['unresolvedTerminals']
    Path('reports/species_key/general-import.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(summary,ensure_ascii=False))


if __name__=='__main__': main()
