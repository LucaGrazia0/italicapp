import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:idb_shim/idb.dart';
import 'observation_database.dart';

/// Scientific packages have their own database; the diary and reviews are never replaced.
class ScientificData {
  static const bundledRevision = 2026110301;
  static const legacyRevision = 2026110301;
  static const paths = [
    'assets/italic/italic_checklist.json',
    'assets/italic/italic_genus_keys.json',
    'assets/italic/flavoparmelia_key.json',
    'assets/italic/character_matrix_v2.json',
    'assets/italic/character_dictionary_v3.json',
    'assets/italic/api_traits_matrix_v2.json',
    'assets/italic/general_reconstructed_key_v1.json',
    'assets/italic/physcia_reconstructed_key_v1.json',
  ];
  static final changes = ValueNotifier<int>(0);
  static Future<void>? _initializing;
  static Database? _db;
  static Map<String, String>? _active;
  static int currentRevision = bundledRevision;
  static String currentVersion = 'Dati inclusi · 3 novembre 2026';

  static Future<void> initialize({IdbFactory? factory}) =>
      _initializing ??= _initialize(factory);
  static Future<void> _initialize(IdbFactory? factory) async {
    try {
      final provider = factory ?? await observationDatabaseFactory();
      if (provider == null) return;
      _db = await provider.open(
        'italicapp_scientific_packages',
        version: 1,
        onUpgradeNeeded: (e) {
          e.database.createObjectStore('packages', keyPath: 'id');
        },
      );
      final tx = _db!.transaction('packages', idbModeReadOnly);
      final active = await tx.objectStore('packages').getObject('active');
      await tx.completed;
      if (active is Map &&
          (active['revision'] as num).toInt() > bundledRevision) {
        currentRevision = (active['revision'] as num).toInt();
        currentVersion = active['version'] as String;
        _active = Map<String, String>.from(active['files'] as Map);
      }
      // Pin the bundled edition once so an APK/data update cannot reinterpret old paths.
      final check = _db!.transaction('packages', idbModeReadOnly);
      final existing = await check
          .objectStore('packages')
          .getObject('revision:$bundledRevision');
      await check.completed;
      if (existing == null) {
        final files = {
          for (final path in paths) path: await rootBundle.loadString(path),
        };
        final write = _db!.transaction('packages', idbModeReadWrite);
        await write.objectStore('packages').put({
          'id': 'revision:$bundledRevision',
          'revision': bundledRevision,
          'version': 'Dati inclusi · 3 novembre 2026',
          'files': files,
        });
        await write.completed;
      }
    } catch (_) {
      // Bundle remains available even when update storage cannot be opened.
      _db = null;
    }
  }

  static Future<String> loadString(String path, {int? revision}) async {
    await initialize();
    if (revision != null &&
        revision != currentRevision &&
        revision != bundledRevision) {
      if (_db == null) {
        throw StateError(
          'Edizione salvata non disponibile. Il percorso originale resta conservato.',
        );
      }
      final tx = _db!.transaction('packages', idbModeReadOnly);
      final old = await tx
          .objectStore('packages')
          .getObject('revision:$revision');
      await tx.completed;
      if (old is Map && old['files'] is Map && old['files'][path] is String) {
        return old['files'][path] as String;
      }
      throw StateError(
        'Edizione salvata non disponibile. Il percorso originale resta conservato.',
      );
    }
    if ((revision == null || revision == currentRevision) &&
        _active?.containsKey(path) == true) {
      return _active![path]!;
    }
    return rootBundle.loadString(path);
  }

  static Future<void> install(
    Map<String, String> files, {
    required int revision,
    required String version,
  }) async {
    await initialize();
    if (_db == null) {
      throw StateError(
        'Archivio aggiornamenti non disponibile. I dati precedenti restano attivi.',
      );
    }
    if (revision <= currentRevision) {
      throw StateError('Questa edizione è già installata.');
    }
    final tx = _db!.transaction('packages', idbModeReadWrite);
    final store = tx.objectStore('packages');
    await store.put({
      'id': 'revision:$revision',
      'revision': revision,
      'version': version,
      'files': files,
    });
    await store.put({
      'id': 'active',
      'revision': revision,
      'version': version,
      'files': files,
    });
    await tx.completed;
    _active = Map.unmodifiable(files);
    currentRevision = revision;
    currentVersion = version;
  }

  static void notifyInstalled() => changes.value++;
  @visibleForTesting
  static Future<void> reset() async {
    _db?.close();
    _db = null;
    _initializing = null;
    _active = null;
    currentRevision = bundledRevision;
    currentVersion = 'Dati inclusi · 3 novembre 2026';
  }
}
