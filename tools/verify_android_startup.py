"""Reject release APKs that cannot register their Android Flutter plugins.

Checking strings is insufficient: the missing registrant is still referenced
by the Flutter engine. Require actual DEX class definitions, not references.
Run this after compiling, before copying an APK to Downloads.
"""
import argparse
import json
from pathlib import Path
import struct
import zipfile

REQUIRED = {'Lit/italic/italicapp/MainActivity;',
            'Lio/flutter/plugins/GeneratedPluginRegistrant;',
            'Lcom/github/dart_lang/jni/JniPlugin;'}


def dex_classes(data):
    if len(data) < 112 or data[:4] != b'dex\n' or data[4:7] not in {
            b'035', b'036', b'037', b'038', b'039', b'040'}:
        raise ValueError('Unsupported or incomplete DEX format')
    strings_n, strings_at = struct.unpack_from('<II', data, 0x38)
    types_n, types_at = struct.unpack_from('<II', data, 0x40)
    classes_n, classes_at = struct.unpack_from('<II', data, 0x60)
    for count, offset, size in [(strings_n, strings_at, 4),
                                (types_n, types_at, 4),
                                (classes_n, classes_at, 32)]:
        if offset < 112 or offset + count * size > len(data):
            raise ValueError('Invalid DEX table bounds')

    def descriptor(index):
        if index >= strings_n:
            raise ValueError('Invalid DEX string index')
        position = struct.unpack_from('<I', data, strings_at + 4 * index)[0]
        for _ in range(5):
            if position >= len(data):
                raise ValueError('Invalid DEX string position')
            byte = data[position]
            position += 1
            if byte & 128 == 0:
                break
        else:
            raise ValueError('Invalid DEX string length')
        end = data.find(b'\0', position)
        if end < 0:
            raise ValueError('Unterminated DEX string')
        return data[position:end].decode('utf-8', errors='replace')

    result = set()
    for i in range(classes_n):
        type_index = struct.unpack_from('<I', data, classes_at + 32 * i)[0]
        if type_index >= types_n:
            raise ValueError('Invalid DEX class index')
        string_index = struct.unpack_from('<I', data, types_at + 4 * type_index)[0]
        result.add(descriptor(string_index))
    return result


def verify(apk):
    classes = set()
    with zipfile.ZipFile(apk) as archive:
        for name in archive.namelist():
            if name.endswith('.dex'):
                classes.update(dex_classes(archive.read(name)))
    missing = REQUIRED - classes
    if missing:
        raise ValueError('Android startup classes missing: ' + ', '.join(sorted(missing))
                         + '. Run flutter pub get with the complete Android project present, then rebuild.')
    return {'startupClassesVerified': sorted(REQUIRED), 'definedClasses': len(classes)}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    args = parser.parse_args()
    print(json.dumps(verify(args.apk), indent=2))
