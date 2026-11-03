import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:italicapp/data/character_matrix_repository.dart';
import 'package:italicapp/data/italic_reference_repository.dart';
import 'package:italicapp/models/identification_path.dart';
import 'package:italicapp/models/observation.dart';
import 'package:italicapp/app_store.dart';
import 'package:italicapp/data/observation_repository.dart';
import 'package:italicapp/pages/reconstructed_key_page.dart';
import 'package:italicapp/services/key_prefilter.dart';
import 'package:italicapp/services/reconstructed_key.dart';

void main() {
  late ReconstructedKey key;
  late CharacterMatrix matrix;
  setUpAll(() {
    final reference =
        (jsonDecode(
                  File(
                    'assets/italic/italic_checklist.json',
                  ).readAsStringSync(),
                )['taxa']
                as List)
            .cast<Map>()
            .map((r) => ItalicTaxon.fromMap(Map<String, dynamic>.from(r)))
            .toList();
    key = ReconstructedKey.fromMap(
      jsonDecode(File(ReconstructedKey.generalAsset).readAsStringSync()) as Map,
      reference,
    );
    matrix = CharacterMatrix.fromMap(
      jsonDecode(File(CharacterMatrixRepository.asset).readAsStringSync())
          as Map,
      reference,
    );
  });
  test(
    'Optional filters combine, reject unsupported guesses and preserve unknowns',
    () {
      final filters = {'growthForm': 'Fol', 'substrata': 'Epiph'};
      final comparison = KeyPrefilter(key, matrix, filters);
      expect(comparison.eligible, contains(1717));
      expect(comparison.coveredLocal, lessThan(key.coveredLocal));
      expect(comparison.excluded, isNotEmpty);
      final withoutData = CharacterMatrix(matrix.characters, []);
      final unknown = KeyPrefilter(key, withoutData, filters);
      expect(unknown.excluded, isEmpty);
      expect(unknown.coveredLocal, key.coveredLocal);
      expect(unknown.uncertain, contains(1717));
      expect(
        KeyPrefilter.normalize({
          'soredia': 'absent',
          'growthForm': 'bogus',
          'photobiont': 'Ch',
        }),
        {'photobiont': 'Ch'},
      );
      final none = KeyPrefilter(key, matrix, {});
      expect(none.excluded, isEmpty);
    },
  );
  test(
    'Pruned tree preserves exact terminals, unresolved source and resumable filters',
    () {
      final comparison = KeyPrefilter(key, matrix, {
        'growthForm': 'Fol',
        'substrata': 'Epiph',
      });
      final filtered = key.filtered(comparison.eligible, comparison.filters);
      expect(filtered.coveredLocal, comparison.coveredLocal);
      expect(filtered.unresolved(filtered.root), key.unresolved(key.root));
      expect(filtered.extraTaxa, key.extraTaxa);
      expect(
        filtered.nodes.values
            .where((n) => !n.terminal)
            .every((n) => n.choices.length == 2),
        isTrue,
      );
      for (final id in filtered.taxa.keys) {
        for (final path in filtered.pathsFor(id)) {
          final input = {
            for (final step in path) step.node.id: step.choice.target,
          };
          expect(filtered.current(input).taxonId, id);
          expect(
            KeyPrefilter.restore(filtered.normalize(input)),
            comparison.filters,
          );
        }
      }
      final physcia = key.forGenus('Physcia');
      final scopedComparison = KeyPrefilter(physcia, matrix, {
        'growthForm': 'Fol',
      });
      final scoped = physcia.filtered(
        scopedComparison.eligible,
        scopedComparison.filters,
      );
      expect(scoped.normalize({})['_genus'], 'Physcia');
      expect(scoped.normalize({})['_trait:growthForm'], 'Fol');
    },
  );
  testWidgets(
    'Back works after resume with no undo history, retaining initial filters',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final scoped = key.forGenus('Physcia');
      final comparison = KeyPrefilter(scoped, matrix, {'growthForm': 'Fol'});
      final filtered = scoped.filtered(comparison.eligible, comparison.filters);
      final path = filtered.pathsFor(1717).first;
      final selections = filtered.normalize({
        for (final s in path.take(2)) s.node.id: s.choice.target,
      });
      final observation =
          Observation(
              id: 'back-test',
              createdAt: DateTime.utc(2026, 11, 2),
              latitude: 45,
              longitude: 11,
              horizontalAccuracy: 4,
            )
            ..identificationPath = IdentificationPath(
              keyId: key.identity,
              answers: const {},
              selections: selections,
              savedAt: DateTime.utc(2026, 11, 2),
            );
      await tester.pumpWidget(
        MaterialApp(
          home: ReconstructedKeyPage(
            definition: key,
            matrix: matrix,
            observation: observation,
            store: AppStore(ObservationRepository()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bivio 3 del tuo percorso'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('reconstructed-back')));
      await tester.pumpAndSettle();
      expect(find.text('Bivio 2 del tuo percorso'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Gruppo e filtri iniziali'),
        -250,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gruppo e filtri iniziali'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Caratteri iniziali:'), findsOneWidget);
      await tester.tap(find.text('Gruppo e filtri iniziali'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('reconstructed-back')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reconstructed-back')));
      await tester.pumpAndSettle();
      expect(find.text('Bivio 1 del tuo percorso'), findsOneWidget);
      expect(observation.identificationPath!.selections, selections);
      expect(tester.takeException(), isNull);
    },
  );
}
