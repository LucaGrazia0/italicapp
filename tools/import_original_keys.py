"""Archive the published textual FRIDA keys; never substitute a generated key.

One isolated cookie session per key is essential: view_external6 uses session
state. Keep the original HTML in cache, and only ship validated text/links.
"""
import argparse
from collections import defaultdict
from datetime import datetime, timezone
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import time
import unicodedata
from urllib.parse import parse_qs, urlparse
from urllib.request import build_opener, HTTPCookieProcessor, Request
from http.cookiejar import CookieJar

ROOT = Path(__file__).resolve().parents[1]
BASE = 'https://italic.units.it/flora/index.php?'
POLICY = 'https://italic.units.it/?c=62&procedure=base&t=61'


class Element:
    def __init__(self, tag='', attrs=()):
        self.tag, self.attrs, self.children = tag, dict(attrs), []

    def text(self):
        return ''.join(c if isinstance(c, str) else c.text() for c in self.children)

    def walk(self, tag):
        for c in self.children:
            if isinstance(c, Element):
                if c.tag == tag:
                    yield c
                yield from c.walk(tag)


class Document(HTMLParser):
    def __init__(self, text):
        super().__init__(convert_charrefs=True)
        self.root = Element()
        self.stack = [self.root]
        self.feed(text)

    def handle_starttag(self, tag, attrs):
        node = Element(tag, attrs)
        self.stack[-1].children.append(node)
        if tag == 'br':
            node.children.append('\n')
        if tag not in {'area', 'base', 'br', 'col', 'embed', 'hr', 'img',
                       'input', 'link', 'meta', 'param', 'source', 'wbr'}:
            self.stack.append(node)

    def handle_endtag(self, tag):
        for i in range(len(self.stack) - 1, 0, -1):
            if self.stack[i].tag == tag:
                del self.stack[i:]
                break

    def handle_data(self, data):
        self.stack[-1].children.append(data)


def clean(value):
    return ' '.join(value.replace('\xa0', ' ').split())


def normalized(value):
    return clean(unicodedata.normalize('NFKC', value)).casefold()


def taxon_index(reference):
    index = defaultdict(set)
    for t in reference:
        for name in [t['scientificName'], *t.get('synonyms', [])]:
            index[normalized(name)].add(t['italicId'])
    return index


def parse_key(text, index):
    doc = Document(text).root
    grouped = defaultdict(list)
    rows = list(doc.walk('tr'))
    for n, row in enumerate(rows):
        cells = [c for c in row.children if isinstance(c, Element) and c.tag == 'td']
        if len(cells) != 3:
            continue
        number, label, result = [clean(c.text()) for c in cells]
        if not number.isdigit() or not label or not result:
            continue
        choice = {'label': label}
        if result.isdigit():
            choice['target'] = int(result)
        else:
            choice['name'] = result
            matches = index.get(normalized(result), set())
            if len(matches) == 1:
                choice['italicId'] = next(iter(matches))
            if n + 1 < len(rows):
                detail = rows[n + 1]
                detail_cells = [c for c in detail.children if isinstance(c, Element) and c.tag == 'td']
                if len(detail_cells) == 1 and detail_cells[0].attrs.get('colspan') == '3':
                    choice['description'] = clean(detail_cells[0].text())
        grouped[int(number)].append(choice)
    if 1 not in grouped:
        raise ValueError('No first couplet in the published textual key')
    if any(len(choices) != 2 for choices in grouped.values()):
        raise ValueError('The published text does not contain two leads per couplet')
    # Allow shared continuations, but reject cycles and disconnected material.
    active, visited, missing = set(), set(), set()

    def visit(number):
        if number in active:
            raise ValueError('Cycle in the published key')
        if number in visited:
            return
        if number not in grouped:
            missing.add(number)
            return
        active.add(number)
        for c in grouped[number]:
            if 'target' in c:
                visit(c['target'])
        active.remove(number)
        visited.add(number)

    visit(1)
    disconnected = sorted(set(grouped) - visited)
    for number in disconnected:
        visit(number)  # Also reject cycles in disconnected source material.
    return ([{'number': n, 'choices': cs} for n, cs in sorted(grouped.items())],
            sorted(missing), disconnected)


def metadata(home, key_id):
    doc = Document(home).root
    # The visible title is a bold element, followed by authors and apparatus.
    title = next((clean(b.text()) for b in doc.walk('b') if clean(b.text())), '')
    if not title:
        title = next((clean(t.text()) for t in doc.walk('title') if clean(t.text())), '')
    if not title:
        raise ValueError('Key title unavailable')
    intro = next((c for c in doc.walk('div') if c.attrs.get('align') == 'justify'), None)
    introduction = clean(intro.text()) if intro else ''
    # Text preceding the introduction contains the visible author credits.
    prefix = home.split('<div align="justify">')[0]
    credit_doc = Document(prefix).root
    centers = list(credit_doc.walk('center'))
    credits = ''
    for c in reversed(centers):
        value = clean(c.text())
        if title in value:
            credits = clean(value.split(title, 1)[1])
            break
    return {'title': title, 'credits': credits, 'introduction': introduction,
            'sourceUrl': f'{BASE}procedure=ext_key_home&key_id={key_id}',
            'license': 'CC BY-SA 4.0', 'licenseSource': POLICY}


def fetch(key_id, directory, refresh=False):
    home_path, text_path = directory / f'{key_id}-home.html', directory / f'{key_id}-text.html'
    if not refresh and home_path.exists() and text_path.exists():
        return home_path.read_bytes(), text_path.read_bytes()
    op = build_opener(HTTPCookieProcessor(CookieJar()))
    op.addheaders = [('User-Agent', 'ItalicGo offline key archiver (https://github.com/LucaGrazia0/italicapp)')]
    home = op.open(f'{BASE}procedure=ext_key_home&key_id={key_id}', timeout=35).read()
    # Follow exactly the form/action offered by the home page.
    if f'procedure=view_external&key_id={key_id}' not in home.decode('utf-8'):
        raise ValueError('No public identify action on this key home page')
    start = op.open(Request(f'{BASE}procedure=view_external&key_id={key_id}', data=b'uno='), timeout=35).read()
    if 'procedure=view_external6' not in start.decode('utf-8'):
        raise ValueError('No public full textual key link')
    text = op.open(BASE + 'procedure=view_external6', timeout=180).read()
    home_path.write_bytes(home)
    text_path.write_bytes(text)
    return home, text


def build(catalogue, reference, directory, selected=None, refresh=False):
    index, keys = taxon_index(reference), []
    ids = sorted({int(parse_qs(urlparse(e['url']).query)['key_id'][0])
                  for e in catalogue['keys']})
    if selected:
        ids = [i for i in ids if i in selected]
    for position, key_id in enumerate(ids, 1):
        failure = None
        for attempt in range(2):
            try:
                home, raw = fetch(key_id, directory, refresh=refresh)
                details = metadata(home.decode('utf-8'), key_id)
                if metadata(raw.decode('utf-8'), key_id)['title'] != details['title']:
                    raise ValueError('Textual key does not match the requested home page')
                nodes, missing, disconnected = parse_key(raw.decode('utf-8'), index)
                item = {'id': key_id, 'status': 'available',
                        **details,
                        'accessedOn': datetime.fromtimestamp((directory / f'{key_id}-text.html').stat().st_mtime, timezone.utc).date().isoformat(),
                        'sha256': hashlib.sha256(raw).hexdigest(),
                        'homeSha256': hashlib.sha256(home).hexdigest(),
                        'nodes': nodes, 'missingTargets': missing,
                        'unreachableCouplets': disconnected}
                keys.append(item)
                print(f'{position}/{len(ids)} {key_id}: {len(nodes)} couplets', flush=True)
                failure = None
                break
            except Exception as error:
                failure = f'{type(error).__name__}: {error}'
                if attempt == 0:
                    time.sleep(1)
        if failure:
            keys.append({'id': key_id, 'status': 'unavailable', 'reason': failure})
            print(f'{position}/{len(ids)} {key_id}: unavailable: {failure}', flush=True)
        time.sleep(.15)
    return {'schemaVersion': 1,
            'source': 'Published ITALIC/FRIDA original textual keys',
            'accessedOn': datetime.now(timezone.utc).date().isoformat(),
            'scope': 'Texts and numbered routes; original online illustrations are not bundled here.',
            'keys': keys}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ids', type=int, nargs='+')
    parser.add_argument('--refresh', action='store_true')
    parser.add_argument('--output', type=Path, default=ROOT / 'assets/italic/original_keys_v1.json')
    args = parser.parse_args()
    directory = ROOT / 'cache/italic_original_keys'
    directory.mkdir(parents=True, exist_ok=True)
    catalogue = json.loads((ROOT / 'assets/italic/italic_genus_keys.json').read_text())
    reference = json.loads((ROOT / 'assets/italic/italic_checklist.json').read_text())['taxa']
    result = build(catalogue, reference, directory, args.ids, args.refresh)
    args.output.write_text(json.dumps(result, ensure_ascii=False, separators=(',', ':')) + '\n')
    print(json.dumps({'keys': len(result['keys']),
                      'available': sum(k['status'] == 'available' for k in result['keys']),
                      'bytes': args.output.stat().st_size}), flush=True)


if __name__ == '__main__':
    main()
