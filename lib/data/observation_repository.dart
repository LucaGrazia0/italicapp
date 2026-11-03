import 'package:idb_shim/idb.dart';
import 'observation_database.dart';
import '../models/observation.dart';

class ObservationRepository {
  ObservationRepository({this.factory});
  final IdbFactory? factory;
  static const _dbName = 'italicapp_observations';
  static const _storeName = 'observations';
  static const _version = 1;

  Database? _db;

  Future<void> close() async {
    _db?.close();
    _db = null;
  }

  Future<Database> _database() async {
    if (_db != null) return _db!;
    final databaseFactory = factory ?? await observationDatabaseFactory();
    if (databaseFactory == null) {
      throw StateError('Archivio locale non disponibile sul dispositivo.');
    }
    _db = await databaseFactory.open(
      _dbName,
      version: _version,
      onUpgradeNeeded: (event) {
        final db = event.database;
        if (!db.objectStoreNames.contains(_storeName)) {
          db.createObjectStore(_storeName, keyPath: 'id');
        }
      },
    );
    return _db!;
  }

  Future<List<Observation>> all() async {
    final db = await _database();
    final txn = db.transaction(_storeName, idbModeReadOnly);
    final values = await txn.objectStore(_storeName).getAll();
    await txn.completed;
    final observations =
        values.whereType<Map>().map(Observation.fromMap).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return observations;
  }

  Future<void> save(Observation observation) async {
    final db = await _database();
    final txn = db.transaction(_storeName, idbModeReadWrite);
    await txn.objectStore(_storeName).put(observation.toMap());
    await txn.completed;
  }

  Future<void> delete(String id) async {
    final db = await _database();
    final txn = db.transaction(_storeName, idbModeReadWrite);
    await txn.objectStore(_storeName).delete(id);
    await txn.completed;
  }
}
