import 'package:idb_shim/idb.dart';
import 'observation_database.dart';
import '../models/character_review.dart';
import '../services/physcia_review_engine.dart';
import 'italic_reference_repository.dart';

class ReviewConflict implements Exception {
  const ReviewConflict();
  @override
  String toString() =>
      'La cella ha una revisione più recente. Riaprila per aggiornare la bozza.';
}

class CharacterReviewRepository {
  CharacterReviewRepository({this.factory});
  final IdbFactory? factory;
  Database? _db;
  Future<void> close() async {
    _db?.close();
    _db = null;
  }

  Future<Database> _database() async {
    if (_db != null) return _db!;
    final provider = factory ?? await observationDatabaseFactory();
    if (provider == null) throw StateError('Archivio locale non disponibile.');
    _db = await provider.open(
      'italicapp_character_reviews',
      version: 1,
      onUpgradeNeeded: (event) {
        event.database.createObjectStore('reviews', keyPath: 'id');
      },
    );
    return _db!;
  }

  Future<List<CharacterReview>> all() async {
    final db = await _database();
    final transaction = db.transaction('reviews', idbModeReadOnly);
    final records = await transaction.objectStore('reviews').getAll();
    await transaction.completed;
    return records.cast<Map>().map(CharacterReview.fromMap).toList();
  }

  Future<void> save(CharacterReview review, ItalicTaxon taxon) async {
    PhysciaPilot.validate(review, taxon);
    final db = await _database();
    final transaction = db.transaction('reviews', idbModeReadWrite);
    final store = transaction.objectStore('reviews');
    final records = (await store.getAll()).cast<Map>().map(
      CharacterReview.fromMap,
    );
    final registry = ReviewRegistry(records);
    final absence = PhysciaPilot.absenceFor(
      registry,
      taxon,
      review.characterId,
    );
    if (absence != null) {
      await transaction.completed;
      throw ReviewNotApplicable(
        PhysciaPilot.character(absence.characterId)!.label,
      );
    }
    final previous = registry.latest(review.taxonId, review.characterId);
    if (review.parentId != previous?.id ||
        review.version != (previous?.version ?? 0) + 1) {
      await transaction.completed;
      throw const ReviewConflict();
    }
    await store.add(review.toMap());
    await transaction.completed;
  }
}

class ReviewNotApplicable implements Exception {
  const ReviewNotApplicable([this.parentLabel = 'Soredi']);
  final String parentLabel;
  @override
  String toString() =>
      '$parentLabel: assenza registrata. Questo carattere non è applicabile. Modifica prima la cella $parentLabel.';
}
