import 'package:idb_shim/idb.dart';
import 'observation_database.dart';

/// Upload checkpoints contain IDs only. Credentials live in secure storage and
/// the diary schema and original photos are never changed by sharing.
class INaturalistUploadRepository {
  INaturalistUploadRepository({this.factory});
  final IdbFactory? factory;
  Future<Database>? _db;
  Future<Database> _database() => _db ??= _open();
  Future<Database> _open() async {
    final provider = factory ?? await observationDatabaseFactory();
    if (provider == null) throw StateError('Archivio locale non disponibile.');
    return provider.open(
      'italicapp_inaturalist',
      version: 1,
      onUpgradeNeeded: (e) =>
          e.database.createObjectStore('uploads', keyPath: 'id'),
    );
  }

  Future<Map<String, Object?>?> read(String id) async {
    final db = await _database();
    final tx = db.transaction('uploads', idbModeReadOnly);
    final value = await tx.objectStore('uploads').getObject(id);
    await tx.completed;
    return value is Map ? Map<String, Object?>.from(value) : null;
  }

  Future<void> write(Map<String, Object?> value) async {
    final db = await _database();
    final tx = db.transaction('uploads', idbModeReadWrite);
    await tx.objectStore('uploads').put(value);
    await tx.completed;
  }

  Future<void> close() async {
    (await _db)?.close();
    _db = null;
  }
}
