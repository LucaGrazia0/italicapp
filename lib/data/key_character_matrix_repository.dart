import 'character_dictionary_repository.dart';
import 'character_matrix_repository.dart';
import 'character_review_repository.dart';
import '../models/character_review.dart';
import '../services/thallus_colour.dart';

/// Adds a source-bound colour view without rewriting scientific assets or edits.
class KeyCharacterMatrixRepository {
  Future<CharacterMatrix> load({int? revision}) async {
    final base = await CharacterMatrixRepository().load(revision: revision);
    final dictionary = await CharacterDictionaryRepository().load(
      revision: revision,
    );
    final reviews = CharacterReviewRepository();
    try {
      return ThallusColour.prepare(
        base,
        dictionary,
        registry: ReviewRegistry(await reviews.all()),
      );
    } catch (_) {
      // Without review storage, do not override any possible suspended colour.
      return base;
    } finally {
      await reviews.close();
    }
  }
}
