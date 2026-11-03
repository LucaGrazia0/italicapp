import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:italicapp/data/italic_reference_repository.dart';
import 'package:italicapp/data/italic_api_traits_repository.dart';
import 'package:italicapp/data/character_matrix_repository.dart';
import 'package:italicapp/services/reconstructed_key.dart';
import 'package:italicapp/services/key_prefilter.dart';

void main() {
  late ReconstructedKey key;
  late CharacterMatrix matrix;
  late ApiTraitsMatrix api;
  setUpAll(() {
    Map read(String n) =>
        jsonDecode(File('assets/italic/$n.json').readAsStringSync()) as Map;
    final reference = (read('italic_checklist')['taxa'] as List)
        .cast<Map>()
        .map((m) => ItalicTaxon.fromMap(Map<String, dynamic>.from(m)))
        .toList();
    key = ReconstructedKey.fromMap(
      read('general_reconstructed_key_v1'),
      reference,
    );
    matrix = CharacterMatrix.fromMap(read('character_matrix_v2'), reference);
    api = ApiTraitsMatrix.fromMap(read('api_traits_matrix_v2'), reference);
  });
  test(
    'Binary presence and absence compare actual API cells and prune the same key candidate set',
    () {
      const id = 'apothecia_lecanorine';
      final yes = KeyPrefilter(key, matrix, {
        'binary:$id': '1',
      }, apiMatrix: api);
      final no = KeyPrefilter(key, matrix, {'binary:$id': '0'}, apiMatrix: api);
      final positive = api.taxa
          .firstWhere((r) => r.values[id] == 1 && !r.needsComparison)
          .taxon
          .italicId!;
      final negative = api.taxa
          .firstWhere((r) => r.values[id] == 0 && !r.needsComparison)
          .taxon
          .italicId!;
      expect(yes.eligible, contains(positive));
      expect(yes.excluded, contains(negative));
      expect(no.excluded, contains(positive));
      expect(no.eligible, contains(negative));
      final filtered = key.filtered(yes.eligible, yes.filters);
      expect(
        filtered.candidates(filtered.root),
        everyElement(isIn(yes.eligible)),
      );
      expect(filtered.normalize({})['_trait:binary:$id'], '1');
      expect(KeyPrefilter.restore(filtered.normalize({})), {'binary:$id': '1'});
    },
  );
  test(
    'Missing API rows and conflicting values are kept as uncertain, including external taxa',
    () {
      final empty = ApiTraitsMatrix(api.characters, []);
      final result = KeyPrefilter(key, matrix, {
        'binary:cortex_k_red': '1',
      }, apiMatrix: empty);
      expect(result.excluded, isEmpty);
      expect(result.uncertain, containsAll(key.taxa.keys));
      final unknown = KeyPrefilter(key, matrix, {}, apiMatrix: api);
      expect(unknown.excluded, isEmpty);
      expect(
        KeyPrefilter.normalize({
          'binary:unknown_column': '1',
          'binary:cortex_k_red': '2',
        }),
        isEmpty,
      );
    },
  );
  test(
    'A conflict affects only its own character and cannot exclude a candidate',
    () {
      final taxon = key.taxa.values.first;
      final evidence = ApiTraitsMatrix(api.characters, [
        ApiTraitRow(
          taxon: taxon,
          values: const {'cortex_k_red': 0, 'apothecia_lecanorine': 1},
          sourceUrl: '',
          retrievedAt: '',
          warning: '',
          schemaIssueCount: 0,
          conflicts: const [
            ApiTraitConflict('cortex_K', 'Contrasto documentato'),
          ],
        ),
      ]);
      final conflicted = KeyPrefilter(key, matrix, {
        'binary:cortex_k_red': '1',
      }, apiMatrix: evidence);
      expect(conflicted.eligible, contains(taxon.italicId));
      expect(conflicted.uncertain, contains(taxon.italicId));
      final other = KeyPrefilter(key, matrix, {
        'binary:apothecia_lecanorine': '0',
      }, apiMatrix: evidence);
      expect(other.excluded, contains(taxon.italicId));
    },
  );
}
