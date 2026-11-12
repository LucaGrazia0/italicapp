import 'package:idb_shim/idb.dart';
import 'observation_database.dart';

class AchievementNoticeState {
  AchievementNoticeState({
    Iterable<int> seen = const [],
    Iterable<int> pending = const [],
  }) : seen = Set.unmodifiable(seen),
       pending = Set.unmodifiable(pending);
  final Set<int> seen, pending;
  Map<String, Object> toMap() => {
    'id': 'notices-v1',
    'seen': seen.toList(),
    'pending': pending.toList(),
  };
  factory AchievementNoticeState.fromMap(Map value) => AchievementNoticeState(
    seen: (value['seen'] as List? ?? []).whereType<int>(),
    pending: (value['pending'] as List? ?? []).whereType<int>(),
  );
}

/// Separate metadata only: never migrates or writes observations or photos.
class AchievementNoticeRepository {
  AchievementNoticeRepository({this.factory});
  final IdbFactory? factory;
  Database? _db;
  Future<Database> _database() async {
    if (_db != null) return _db!;
    final provider = factory ?? await observationDatabaseFactory();
    if (provider == null) throw StateError('Archivio locale non disponibile.');
    _db = await provider.open(
      'italicapp_achievements',
      version: 1,
      onUpgradeNeeded: (e) =>
          e.database.createObjectStore('notices', keyPath: 'id'),
    );
    return _db!;
  }

  Future<AchievementNoticeState?> read() async {
    final db = await _database();
    final tx = db.transaction('notices', idbModeReadOnly);
    final value = await tx.objectStore('notices').getObject('notices-v1');
    await tx.completed;
    return value is Map ? AchievementNoticeState.fromMap(value) : null;
  }

  Future<void> write(AchievementNoticeState value) async {
    final db = await _database();
    final tx = db.transaction('notices', idbModeReadWrite);
    await tx.objectStore('notices').put(value.toMap());
    await tx.completed;
  }

  Future<void> close() async {
    _db?.close();
    _db = null;
  }
}
