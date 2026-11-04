import 'package:flutter_test/flutter_test.dart';
import 'package:italicapp/data/character_dictionary_repository.dart';
import 'package:italicapp/data/character_matrix_repository.dart';
import 'package:italicapp/data/italic_reference_repository.dart';
import 'package:italicapp/data/scientific_data.dart';
import 'package:italicapp/data/revision_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Parsed scientific models are reused and are refreshed on a data update',
    () async {
      final a = ItalicReferenceRepository();
      await a.load();
      final b = ItalicReferenceRepository();
      await b.load();
      expect(identical(a.taxa, b.taxa), true);
      final dictionary = CharacterDictionaryRepository();
      final d = await dictionary.load();
      expect(identical(d, await dictionary.load()), true);
      final matrix = CharacterMatrixRepository();
      final m = await matrix.load();
      expect(identical(m, await matrix.load()), true);
      ScientificData.changes.value++;
      final c = ItalicReferenceRepository();
      await c.load();
      expect(identical(a.taxa, c.taxa), false);
      expect(c.taxa.length, a.taxa.length);
      expect(identical(d, await dictionary.load()), false);
      expect(identical(m, await matrix.load()), false);
    },
  );
  test(
    'Concurrent readers share one parse; failed loads can be retried',
    () async {
      final cache = RevisionCache<int>();
      var calls = 0;
      Future<int> read(int revision) async {
        calls++;
        return revision;
      }

      final values = await Future.wait([cache.load(read), cache.load(read)]);
      expect(values[0], values[1]);
      expect(calls, 1);
      cache.clear();
      await expectLater(
        cache.load((_) async => throw StateError('retry')),
        throwsStateError,
      );
      expect(await cache.load(read), ScientificData.currentRevision);
      expect(calls, 2);
    },
  );
}
