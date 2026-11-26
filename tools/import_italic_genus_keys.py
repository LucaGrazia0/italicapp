#!/usr/bin/env python3
"""Export only genus names and official key URLs from the supplied SQL dump."""
import argparse
import json
from pathlib import Path
import re
from urllib.parse import parse_qs, urlparse

from import_italic_ecology import parse_tuple

ROOT = Path(__file__).resolve().parents[1]


def read_keys(path):
    active = False
    keys = {}
    with Path(path).open(encoding='utf-8') as source:
        for line in source:
            header = re.match(r'INSERT INTO `([^`]+)` \((.*?)\) VALUES', line)
            if header:
                active = header[1] == 'Generi_note'
                columns = re.findall(r'`([^`]+)`', header[2])
                continue
            if active and line.startswith('('):
                values = parse_tuple(line)
                if len(values) != len(columns):
                    raise ValueError('Unexpected Generi_note column count')
                row = dict(zip(columns, values))
                url = (row.get('chiave') or '').strip()
                if not url:
                    continue
                parsed = urlparse(url)
                query = parse_qs(parsed.query)
                if (parsed.scheme != 'https' or parsed.netloc != 'italic.units.it'
                        or parsed.path != '/flora/index.php'
                        or query.get('procedure') != ['ext_key_home']
                        or not query.get('key_id', [''])[0].isdigit()):
                    raise ValueError(f'Unsupported official key URL for row {row["ID"]}')
                match = re.match(r'([A-Z][a-z]+)\b', (row.get('genus') or '').strip())
                if not match:
                    raise ValueError('Unrecognized genus name')
                genus = match[1]
                if row['ID'] in keys:
                    raise ValueError('Duplicate genus record ID')
                keys[row['ID']] = {'id': row['ID'], 'genus': genus, 'name': row['genus'].strip(), 'url': url}
            if active and line.rstrip().endswith(';'):
                active = False
    if not keys:
        raise ValueError('No official genus keys found')
    return sorted(keys.values(), key=lambda item: (item['genus'].lower(), item['name'].lower()))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sql', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=ROOT / 'assets/italic/italic_genus_keys.json')
    args = parser.parse_args()
    keys = read_keys(args.sql)
    payload = {'metadata': {'source': 'ITALIC SQL: Generi_note', 'count': len(keys),
        'content': 'Official key links; original offline text is bundled separately in original_keys_v1.json'}, 'keys': keys}
    args.output.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'Exported {len(keys)} official genus key links')


if __name__ == '__main__':
    main()
