import 'dart:convert';
import 'dart:typed_data';
import '../brand.dart';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../data/scientific_data.dart';
import '../data/italic_reference_repository.dart';
import '../data/character_matrix_repository.dart';
import '../data/italic_api_traits_repository.dart';
import '../data/identification_repository.dart';
import 'character_dictionary.dart';
import 'identification_engine.dart';
import 'reconstructed_key.dart';

class DataRelease {
  const DataRelease({
    required this.revision,
    required this.version,
    required this.bytes,
    required this.sha256Hash,
    required this.dataUrl,
    required this.minimumAppBuild,
    this.apkUrl,
    this.appBuild = 19,
  });
  final int revision, bytes, minimumAppBuild, appBuild;
  final String version, sha256Hash;
  final Uri dataUrl;
  final Uri? apkUrl;
  static bool trusted(Uri uri) =>
      uri.scheme == 'https' &&
      uri.host == 'github.com' &&
      uri.path.startsWith('/LucaGrazia0/italicapp/releases/download/') &&
      uri.userInfo.isEmpty &&
      !uri.hasPort;
  factory DataRelease.fromMap(Map raw) {
    final url = Uri.parse(raw['dataUrl'] as String);
    final apk = raw['apkUrl'] == null
        ? null
        : Uri.parse(raw['apkUrl'] as String);
    final length = raw['bytes'] as int;
    if (raw['schemaVersion'] != 1 ||
        length <= 0 ||
        length > 70 * 1024 * 1024 ||
        !trusted(url) ||
        (apk != null && !trusted(apk)) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(raw['sha256'] as String)) {
      throw const FormatException('Pacchetto di aggiornamento non valido.');
    }
    return DataRelease(
      revision: raw['revision'] as int,
      version: raw['version'] as String,
      bytes: length,
      sha256Hash: raw['sha256'] as String,
      dataUrl: url,
      minimumAppBuild: raw['minimumAppBuild'] as int,
      appBuild: raw['appBuild'] as int? ?? 19,
      apkUrl: apk,
    );
  }
}

class DataUpdates {
  DataUpdates({http.Client? client}) : client = client ?? http.Client();
  final http.Client client;
  static const appBuild = AppBrand.build;
  static final feed = Uri.parse(
    'https://api.github.com/repos/LucaGrazia0/italicapp/releases/latest',
  );
  Future<DataRelease?> check() async {
    final response = await client
        .get(feed, headers: {'Accept': 'application/vnd.github+json'})
        .timeout(const Duration(seconds: 20));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw StateError(
        'Controllo aggiornamenti non disponibile. Riprova con una connessione attiva.',
      );
    }
    final body = jsonDecode(response.body) as Map;
    final assets = (body['assets'] as List).whereType<Map>().where(
      (a) => a['name'] == 'italicapp-data-manifest.json',
    );
    if (assets.isEmpty) return null;
    final uri = Uri.parse(assets.first['browser_download_url'] as String);
    if (!DataRelease.trusted(uri)) {
      throw const FormatException('Fonte aggiornamento non riconosciuta.');
    }
    final manifest = await client.get(uri).timeout(const Duration(seconds: 20));
    if (manifest.statusCode != 200 || manifest.bodyBytes.length > 65536) {
      throw const FormatException('Manifesto non disponibile.');
    }
    return DataRelease.fromMap(
      jsonDecode(utf8.decode(manifest.bodyBytes)) as Map,
    );
  }

  static Map<String, String> validate(List<int> bytes, DataRelease release) {
    if (bytes.length != release.bytes ||
        sha256.convert(bytes).toString() != release.sha256Hash) {
      throw const FormatException(
        'Download incompleto o non corrispondente alla versione pubblicata.',
      );
    }
    final bundle = jsonDecode(utf8.decode(bytes)) as Map;
    if (bundle['schemaVersion'] != 1 ||
        bundle['revision'] != release.revision) {
      throw const FormatException('Versione dei dati non corrispondente.');
    }
    final files = Map<String, String>.from(bundle['files'] as Map);
    if (files.length != ScientificData.paths.length ||
        !ScientificData.paths.every(files.containsKey)) {
      throw const FormatException(
        'Il pacchetto non contiene tutti gli archivi scientifici.',
      );
    }
    Map read(String name) =>
        jsonDecode(files['assets/italic/$name.json']!) as Map;
    final checklist = read('italic_checklist');
    final reference = (checklist['taxa'] as List)
        .cast<Map>()
        .map((m) => ItalicTaxon.fromMap(Map<String, dynamic>.from(m)))
        .toList();
    if (reference.isEmpty ||
        reference.length > 15000 ||
        reference.map((t) => t.italicId).toSet().length != reference.length) {
      throw const FormatException('Checklist non valida.');
    }
    CharacterMatrix.fromMap(read('character_matrix_v2'), reference);
    ApiTraitsMatrix.fromMap(read('api_traits_matrix_v2'), reference);
    CharacterDictionary.fromMap(read('character_dictionary_v3'));
    ReconstructedKey.fromMap(read('general_reconstructed_key_v1'), reference);
    ReconstructedKey.fromMap(read('physcia_reconstructed_key_v1'), reference);
    IdentificationKey.fromMap(
      Map<String, dynamic>.from(read('flavoparmelia_key')),
    );
    final keys = read('italic_genus_keys')['keys'] as List;
    if (keys.any((k) => k is! Map || GenusKey.fromMap(k) == null)) {
      throw const FormatException('Catalogo chiavi non valido.');
    }
    return files;
  }

  Future<void> install(
    DataRelease release, {
    void Function(double)? progress,
  }) async {
    if (release.minimumAppBuild > appBuild) {
      throw StateError('Per questi dati serve prima aggiornare l’APK.');
    }
    final response = await client
        .send(http.Request('GET', release.dataUrl))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw StateError(
        'Download non disponibile. I dati attuali restano utilizzabili.',
      );
    }
    final buffer = BytesBuilder(copy: false);
    var received = 0;
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 35),
    )) {
      received += chunk.length;
      if (received > release.bytes) {
        throw const FormatException('Dimensione del download non valida.');
      }
      buffer.add(chunk);
      progress?.call(received / release.bytes);
    }
    final files = await compute(_validateRequest, (
      buffer.takeBytes(),
      release,
    ));
    await ScientificData.install(
      files,
      revision: release.revision,
      version: release.version,
    );
    ReconstructedKey.clearCache();
    GenusKeyCatalog.clearCache();
    ScientificData.notifyInstalled();
  }

  void close() => client.close();
}

Map<String, String> _validateRequest((Uint8List, DataRelease) request) =>
    DataUpdates.validate(request.$1, request.$2);
