"""Package the verified web release and bundled runtimes for other computers."""

import argparse
import hashlib
import json
import re
import stat
import zipfile
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]

MAC_LAUNCHER = '''#!/bin/zsh
APP_DIR="${0:A:h}"
case "$(/usr/bin/uname -m)" in
  arm64) RUNTIME="$APP_DIR/runtime/arm64/bin/python3" ;;
  x86_64) RUNTIME="$APP_DIR/runtime/x64/bin/python3" ;;
  *) printf 'Questo Mac non è supportato.\n'; exit 1 ;;
esac
printf '\\033]0;Italic Go\\007'
"$RUNTIME" -I "$APP_DIR/tools/launch_desktop.py" "$@"
result=$?
if (( result != 0 )); then
  printf '\\nAvvio non riuscito. Consulta LEGGIMI.txt nella cartella dell’app.\\n'
  read -r '?Premi Invio per chiudere. '
fi
exit "$result"
'''

WINDOWS_LAUNCHER = r'''@echo off
setlocal DisableDelayedExpansion
title Italic Go
set "APP_DIR=%~dp0"
set "RUNTIME=%APP_DIR%runtime\x64\python.exe"
if /I "%PROCESSOR_ARCHITECTURE%"=="ARM64" set "RUNTIME=%APP_DIR%runtime\arm64\python.exe"
if /I "%PROCESSOR_ARCHITEW6432%"=="ARM64" set "RUNTIME=%APP_DIR%runtime\arm64\python.exe"
"%RUNTIME%" -I "%APP_DIR%tools\launch_desktop.py" %*
if errorlevel 1 (
  echo.
  echo Avvio non riuscito. Consulta LEGGIMI.txt nella cartella dell'app.
  pause
  exit /b 1
)
endlocal
'''

INSTRUCTIONS = '''ITALIC GO {version} — {platform} PORTATILE

AVVIO SU UN ALTRO COMPUTER
1. Trasferisci lo ZIP completo ed estrai tutta la cartella.
2. Conserva la cartella in una posizione stabile, per esempio Documenti.
3. Fai doppio clic su "{launcher}".
4. Italic Go si apre nel browser predefinito. Lascia aperta la finestra
   del terminale durante l'uso; per chiudere il server premi Ctrl+C.

Non aprire index.html direttamente e non avviare il file dentro lo ZIP.
Non separare il file di avvio dalle cartelle web, runtime e tools.
Python è già incluso: non occorrono Python, Flutter, Xcode, Android Studio,
un account GitHub o installazioni come amministratore.

{platform_notes}

COSA INCLUDE
Stessa versione 0.8.23 dell'APK: diario, plot, traguardi, filtri,
chiave generale, matrici, 149 chiavi originali e 3.406 foto di specie.
La copia dell'app e i dati inclusi funzionano senza internet già al primo avvio.
Mappe, ricerca di località, collegamenti esterni e servizi online richiedono rete.
Sul computer le foto si aggiungono dai file o dalla webcam, se disponibile.
La posizione dipende dal browser e dall'hardware: il computer può non avere
un GPS o una quota satellitare. È disponibile la scelta del punto sulla mappa.
La condivisione usa le possibilità del browser; in alternativa scarica
l'esportazione e caricala nel servizio desiderato. Il collegamento nativo
all'app iNaturalist del telefono non è disponibile in questa edizione.

DIARIO E DATI PERSONALI
Usa sempre http://127.0.0.1:8782/ nello stesso browser e profilo.
Il diario resta nei dati del browser di quel computer, non nello ZIP.
Non usare la navigazione privata e non cancellare i dati del sito.
Spostare o inviare lo ZIP NON trasferisce il diario e le tue fotografie.
Questo pacchetto contiene l'app e le foto scientifiche; non contiene diari,
fotografie personali, password o credenziali dell'autore.
Su un Mac che usava la precedente edizione portatile, lo stesso indirizzo
e browser permettono di continuare a usare il diario già presente.
Per aggiornare chiudi la precedente finestra con Ctrl+C, estrai lo ZIP nuovo
in una nuova cartella e avvialo mantenendo browser e indirizzo.

SE NON SI APRE
Se la porta 8782 è occupata, chiudi il vecchio server di Italic Go e riprova.
Non cambiamo automaticamente porta: questo creerebbe un altro diario.
Il server ascolta solo su 127.0.0.1, senza esporre l'app sulla rete locale.
L'apertura del browser non richiede una connessione internet.

CONTENUTO E LICENZE
EDIZIONE.json identifica la versione; CONTENUTO.json elenca gli hash dei file.
Licenze e attribuzioni dei dati e delle fotografie sono consultabili nell'app.
Le licenze dei runtime Python inclusi sono nelle rispettive cartelle runtime.
RUNTIME-SOURCES.json documenta distributori e hash dei download verificati.
'''

NOTES = {
    'Mac': '''REQUISITI MAC
Mac Intel oppure Apple Silicon; macOS 12 o successivo e browser aggiornato
(Safari, Chrome o Firefox). Il runtime adatto viene scelto automaticamente.
Il lanciatore non è firmato/autenticato da Apple: se macOS ne blocca l'avvio,
consulta Impostazioni di Sistema > Privacy e sicurezza per autorizzare
questa copia, solo se ricevuta da una fonte di cui ti fidi. Non è necessario
disattivare le protezioni del Mac. Eventuali blocchi del runtime incluso
vanno autorizzati attraverso lo stesso pannello secondo il messaggio di macOS.''',
    'Windows': '''REQUISITI WINDOWS
Windows 10 o 11 a 64 bit, PC Intel/AMD oppure ARM64, con Edge, Chrome
o Firefox aggiornato. Il runtime adatto viene scelto automaticamente.
I PC Windows a 32 bit non sono supportati. In Esplora file scegli
"Estrai tutto" prima di aprire il lanciatore .cmd. Le regole di sicurezza
di computer aziendali potrebbero richiedere l'autorizzazione dell'amministratore.''',
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def web_resources(web):
    match = re.search(r'const PACK = (\{[^\n]+\});\n',
                      (web / 'italic_offline_worker.js').read_text())
    if not match:
        raise ValueError('Manifesto offline non trovato')
    pack = json.loads(match[1])
    resources = {}
    for entry in pack['resources']:
        relative = PurePosixPath(entry['path'])
        if relative.is_absolute() or '..' in relative.parts:
            raise ValueError('Percorso non valido')
        source = web.joinpath(*relative.parts)
        if digest(source.read_bytes()) != entry['sha256']:
            raise ValueError('Risorsa modificata: ' + str(relative))
        resources['web/' + str(relative)] = source
    for name in ('italic_offline_worker.js', 'flutter_service_worker.js', 'version.json'):
        resources['web/' + name] = web / name
    return pack, resources


def package(web, runtimes, destination, platform):
    pack, resources = web_resources(web)
    info = json.loads((web / 'version.json').read_text())
    version, build = info['version'], int(info['build_number'])
    expected = re.search(r'^version: (\S+)', (ROOT / 'pubspec.yaml').read_text(), re.M)[1]
    if f'{version}+{build}' != expected:
        raise ValueError('La build web non corrisponde alla versione dei sorgenti')
    if destination.exists():
        raise FileExistsError(str(destination))
    folder = f'Italic Go {version} {platform}'
    launcher = 'Apri Italic Go.command' if platform == 'Mac' else 'Apri Italic Go.cmd'
    files = {**resources, 'tools/launch_desktop.py': ROOT / 'tools/launch_desktop.py'}
    sources = json.loads((runtimes / 'runtime-sources.json').read_text())
    prefix = 'mac' if platform == 'Mac' else 'windows'
    for arch in ('x64', 'arm64'):
        root = runtimes / f'{prefix}-{arch}'
        if platform == 'Mac':
            root /= 'python'
        executable = root / ('bin/python3' if platform == 'Mac' else 'python.exe')
        if not executable.is_file():
            raise ValueError('Runtime mancante: ' + str(executable))
        for source in sorted(root.rglob('*')):
            if source.is_file() and '__pycache__' not in source.parts:
                if source.is_symlink() or not source.resolve().is_relative_to(root.resolve()):
                    raise ValueError('Il runtime deve contenere solo file interni')
                files[f'runtime/{arch}/{source.relative_to(root).as_posix()}'] = source
    descriptor = {'app': 'Italic Go', 'version': version, 'build': build,
                  'platform': platform, 'edition': 'portable-local-web',
                  'offlinePack': pack['version'], 'origin': 'http://127.0.0.1:8782/'}
    generated = {
        launcher: (MAC_LAUNCHER if platform == 'Mac' else WINDOWS_LAUNCHER).replace(
            '\n', '\r\n' if platform == 'Windows' else '\n').encode(),
        'LEGGIMI.txt': INSTRUCTIONS.format(version=version, platform=platform,
            launcher=launcher, platform_notes=NOTES[platform]).encode('utf-8'),
        'EDIZIONE.json': json.dumps(descriptor, indent=2).encode(),
        'RUNTIME-SOURCES.json': json.dumps([s for s in sources if s['platform'].startswith(prefix + '-')], indent=2).encode(),
    }
    records = []
    destination.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(destination, 'x', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for relative in sorted(set(files) | set(generated)):
            source = files.get(relative)
            data = source.read_bytes() if source else generated[relative]
            mode = source.stat().st_mode if source else (0o755 if relative.endswith('.command') else 0o644)
            entry = zipfile.ZipInfo(folder + '/' + relative)
            entry.create_system = 3
            entry.external_attr = (stat.S_IFREG | (mode & 0o777)) << 16
            entry.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(entry, data)
            records.append({'path': relative, 'sha256': digest(data), 'bytes': len(data)})
        archive.writestr(folder + '/CONTENUTO.json', json.dumps(
            {**descriptor, 'files': records}, ensure_ascii=False, indent=2))
    result = {**descriptor, 'file': str(destination), 'bytes': destination.stat().st_size,
              'sha256': digest(destination.read_bytes()), 'files': len(records) + 1,
              'originalKeysSha256': digest((web / 'assets/assets/italic/original_keys_v1.json').read_bytes())}
    destination.with_suffix('.zip.sha256').write_text(result['sha256'] + '  ' + destination.name + '\n')
    destination.with_suffix('.zip.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2), flush=True)
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--web', type=Path, required=True)
    parser.add_argument('--runtimes', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--platform', choices=['Mac', 'Windows'], required=True)
    args = parser.parse_args()
    package(args.web.resolve(), args.runtimes.resolve(), args.output.resolve(), args.platform)
