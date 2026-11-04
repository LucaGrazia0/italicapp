import 'package:idb_shim/idb.dart';
import 'observation_database.dart';
import '../models/field_plot.dart';

/// Plots use a separate local database. Existing diary and review schemas stay compatible.
class PlotRepository {
  PlotRepository({this.factory});
  final IdbFactory? factory;
  Database? _db;
  Future<Database> _database() async {
    if (_db != null) return _db!;
    final provider = factory ?? await observationDatabaseFactory();
    if (provider == null) throw StateError('Archivio plot non disponibile.');
    return _db = await provider.open(
      'italicapp_plots',
      version: 1,
      onUpgradeNeeded: (event) {
        event.database.createObjectStore('plots', keyPath: 'id');
        event.database.createObjectStore('metadata');
      },
    );
  }

  Future<List<FieldPlot>> all() async {
    final db = await _database();
    final tx = db.transaction('plots', idbModeReadOnly);
    final rows = await tx.objectStore('plots').getAll();
    await tx.completed;
    return rows.whereType<Map>().map(FieldPlot.fromMap).toList()
      ..sort((a, b) => b.sampledAt.compareTo(a.sampledAt));
  }

  Future<void> save(FieldPlot plot) async {
    final db = await _database();
    final tx = db.transaction('plots', idbModeReadWrite);
    await tx.objectStore('plots').put(plot.toMap());
    await tx.completed;
  }

  Future<String?> pendingPhotoPlot() async {
    final db = await _database();
    final tx = db.transaction('metadata', idbModeReadOnly);
    final value = await tx
        .objectStore('metadata')
        .getObject('pendingPhotoPlot');
    await tx.completed;
    return value is String ? value : null;
  }

  Future<void> setPendingPhotoPlot(String? id) async {
    final db = await _database();
    final tx = db.transaction('metadata', idbModeReadWrite);
    if (id == null) {
      await tx.objectStore('metadata').delete('pendingPhotoPlot');
    } else {
      await tx.objectStore('metadata').put(id, 'pendingPhotoPlot');
    }
    await tx.completed;
  }

  Future<Map?> pendingDeletion() async {
    final db = await _database();
    final tx = db.transaction('metadata', idbModeReadOnly);
    final value = await tx.objectStore('metadata').getObject('plotDeletion');
    await tx.completed;
    return value is Map ? value : null;
  }

  Future<void> beginDeletion(FieldPlot plot, bool deletePhotos) async {
    if (await pendingDeletion() != null) {
      throw StateError('Completa prima la precedente eliminazione.');
    }
    final db = await _database();
    final tx = db.transaction('metadata', idbModeReadWrite);
    await tx.objectStore('metadata').put({
      'plot': plot.toMap(),
      'deletePhotos': deletePhotos,
    }, 'plotDeletion');
    await tx.completed;
  }

  Future<void> finishDeletion(String id) async {
    final db = await _database();
    final tx = db.transactionList(['plots', 'metadata'], idbModeReadWrite);
    await tx.objectStore('plots').delete(id);
    await tx.objectStore('metadata').delete('plotDeletion');
    final pending = await tx
        .objectStore('metadata')
        .getObject('pendingPhotoPlot');
    if (pending == id) {
      await tx.objectStore('metadata').delete('pendingPhotoPlot');
    }
    await tx.completed;
  }

  Future<void> close() async {
    _db?.close();
    _db = null;
  }
}
