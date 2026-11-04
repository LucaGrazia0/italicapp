"""Read this project's GitHub Actions status/downloads using configured Git auth.

Credentials stay in memory; signed artifact URLs and tokens are never printed.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import urllib.error
import urllib.parse
import urllib.request
import zipfile

REPO = 'LucaGrazia0/italicapp'


def credential():
    result = subprocess.run(['git', 'credential', 'fill'], input='protocol=https\nhost=github.com\n\n',
                            text=True, capture_output=True, check=True)
    return dict(line.split('=', 1) for line in result.stdout.splitlines() if '=' in line)['password']


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def request(path, redirect=True):
    req = urllib.request.Request('https://api.github.com/repos/' + REPO + '/' + path,
                                 headers={'Authorization': 'Bearer ' + credential(),
                                          'Accept': 'application/vnd.github+json',
                                          'X-GitHub-Api-Version': '2022-11-28'})
    if redirect:
        with urllib.request.urlopen(req, timeout=30) as response:
            return json.load(response)
    return urllib.request.build_opener(NoRedirect).open(req, timeout=30)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=['runs', 'jobs', 'artifacts', 'download'])
    parser.add_argument('--run', type=int)
    parser.add_argument('--artifact', type=int)
    parser.add_argument('--destination', type=Path)
    args = parser.parse_args()
    if args.command == 'runs':
        data = request('actions/runs?branch=codex%2Fios-ipa-0.8.10&per_page=5')
        print(json.dumps([{k: r.get(k) for k in ('id', 'status', 'conclusion', 'head_sha', 'html_url', 'created_at')}
                          for r in data['workflow_runs']], indent=2))
    elif args.command == 'jobs':
        jobs = request(f'actions/runs/{args.run}/jobs')['jobs']
        print(json.dumps([{k: j.get(k) for k in ('id', 'status', 'conclusion', 'steps')} for j in jobs], indent=2))
    elif args.command == 'artifacts':
        print(json.dumps(request(f'actions/runs/{args.run}/artifacts'), indent=2))
    else:
        try:
            request(f'actions/artifacts/{args.artifact}/zip', redirect=False)
            raise ValueError('Expected an authenticated download redirect.')
        except urllib.error.HTTPError as response:
            if response.code != 302:
                raise
            url = response.headers['Location']
        if urllib.parse.urlparse(url).scheme != 'https':
            raise ValueError('Invalid artifact download URL.')
        args.destination.mkdir(parents=True, exist_ok=True)
        temporary = args.destination / 'github-ios-artifact.zip'
        # The redirected request intentionally has no Authorization header.
        with urllib.request.urlopen(url, timeout=120) as response, temporary.open('wb') as out:
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                out.write(chunk)
        with zipfile.ZipFile(temporary) as archive:
            for name in archive.namelist():
                path = Path(name)
                if path.name != name or not name.startswith('Italicapp-0.8.10-iPhone-non-firmata.ipa'):
                    raise ValueError('Unexpected artifact member.')
                (args.destination / name).write_bytes(archive.read(name))
        ipa = args.destination / 'Italicapp-0.8.10-iPhone-non-firmata.ipa'
        report = json.loads(ipa.with_suffix('.ipa.json').read_text())
        if hashlib.sha256(ipa.read_bytes()).hexdigest() != report['sha256']:
            raise ValueError('IPA download checksum mismatch.')
        print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
