"""Package a real iPhoneOS Runner.app; reject APKs and simulator binaries."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import struct
import zipfile


def package(app, destination, version, build):
    app, destination = Path(app), Path(destination)
    if not app.is_dir() or app.suffix != '.app':
        raise ValueError('Serve un bundle iPhoneOS .app compilato da Xcode.')
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    if (info.get('CFBundleIdentifier') != 'it.italic.italicapp' or
            info.get('CFBundleShortVersionString') != version or
            info.get('CFBundleVersion') != str(build) or
            info.get('CFBundleSupportedPlatforms') != ['iPhoneOS']):
        raise ValueError('Versione, identità o piattaforma iPhoneOS non corrispondente.')
    binary = (app / info['CFBundleExecutable']).read_bytes()
    if len(binary) < 32 or struct.unpack('<II', binary[:8]) != (0xfeedfacf, 0x100000c):
        raise ValueError('Il programma non è un eseguibile Mach-O arm64 per iPhone.')
    commands = struct.unpack('<I', binary[16:20])[0]
    position, ios = 32, False
    for _ in range(commands):
        command, length = struct.unpack('<II', binary[position:position + 8])
        if length < 8 or position + length > len(binary):
            raise ValueError('Eseguibile Mach-O incompleto.')
        if command == 0x32:
            ios = struct.unpack('<I', binary[position + 8:position + 12])[0] == 2
        if command == 0x25:
            ios = True
        position += length
    if not ios:
        raise ValueError('Il programma non è destinato a un iPhone fisico.')
    assets = app / 'Frameworks/App.framework/flutter_assets'
    catalogue = json.loads((assets / 'assets/italic/species_photos_v1.json').read_text())
    for photo in catalogue['photos']:
        path = Path(photo['asset'])
        if path.is_absolute() or '..' in path.parts:
            raise ValueError('Percorso fotografico non valido.')
        if hashlib.sha256((assets / path).read_bytes()).hexdigest() != photo['sha256']:
            raise ValueError('Foto offline incompleta: ' + str(photo['italicId']))
    destination.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(destination, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in sorted(app.rglob('*')):
            if path.is_symlink():
                raise ValueError('Symlink inatteso nel bundle iPhoneOS.')
            if path.is_file():
                archive.write(path, 'Payload/' + app.name + '/' + path.relative_to(app).as_posix())
    digest = hashlib.sha256(destination.read_bytes()).hexdigest()
    report = {'version': version, 'build': str(build), 'bundleIdentifier': info['CFBundleIdentifier'],
              'platform': 'iPhoneOS', 'architecture': 'arm64', 'signedForInstallation': False,
              'photoChecksumsVerified': len(catalogue['photos']), 'sha256': digest,
              'bytes': destination.stat().st_size,
              'installation': 'Requires signing/provisioning, for example through a compatible sideloading tool.'}
    destination.with_suffix('.ipa.json').write_text(json.dumps(report, indent=2) + '\n')
    destination.with_suffix('.ipa.sha256').write_text(digest + '  ' + destination.name + '\n')
    print(json.dumps(report, indent=2))
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('destination', type=Path)
    parser.add_argument('--version', required=True)
    parser.add_argument('--build', required=True)
    args = parser.parse_args()
    package(args.app, args.destination, args.version, args.build)
