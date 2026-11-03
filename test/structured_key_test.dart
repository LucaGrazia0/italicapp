import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:italicapp/app_store.dart';
import 'package:italicapp/data/character_matrix_repository.dart';
import 'package:italicapp/data/italic_reference_repository.dart';
import 'package:italicapp/data/observation_repository.dart';
import 'package:italicapp/data/character_review_repository.dart';
import 'package:italicapp/models/identification_path.dart';
import 'package:italicapp/models/observation.dart';
import 'package:italicapp/pages/character_matrix_page.dart';
import 'package:italicapp/pages/structured_key_page.dart';
import 'package:italicapp/services/structured_key_engine.dart';
import 'package:italicapp/theme/app_theme.dart';

void main() {
  final engine = StructuredKey();
  final choices = {
    'growthForm': 'Fol',
    'photobiont': 'Ch',
    'reproductiveStrategy': 'A.s',
    'substrata': 'Epiph',
  };
  late CharacterMatrix fullMatrix;
  late CharacterMatrix small;
  setUpAll(() {
    final taxa =
        (jsonDecode(
                  File(
                    'assets/italic/italic_checklist.json',
                  ).readAsStringSync(),
                )['taxa']
                as List)
            .cast<Map>()
            .map((m) => ItalicTaxon.fromMap(Map<String, dynamic>.from(m)))
            .toList();
    fullMatrix = CharacterMatrix.fromMap(
      jsonDecode(
        File('assets/italic/character_matrix_v2.json').readAsStringSync(),
      ),
      taxa,
    );
    small = CharacterMatrix(fullMatrix.characters, [
      _row(1, {
        'growthForm': 'Fol.b',
        'photobiont': 'Ch',
        'reproductiveStrategy': 'A.s',
        'substrata': 'Epiph-Lign',
      }),
      _row(2, {
        'growthForm': 'Cr',
        'photobiont': 'Tr',
        'reproductiveStrategy': 'S',
        'substrata': 'Sax',
      }),
      _row(3, {}),
    ]);
  });

  test('Only the four structured columns filter real checklist taxa', () {
    expect(StructuredKey.questions.map((q) => q.id), [
      'growthForm',
      'photobiont',
      'reproductiveStrategy',
      'substrata',
    ]);
    final result = engine.evaluate(fullMatrix, choices);
    expect(result.activeCriteria, 4);
    expect(result.matching.length, greaterThan(2));
    expect(
      result.matching.map((a) => a.row.taxon.italicId),
      containsAll([978, 979]),
    );
    expect(
      result.matching.length +
          result.uncertain.length +
          result.different.length,
      3588,
    );
    expect(
      result.matching.every(
        (a) => a.criteria.every((c) => c.status == StructuredMatch.match),
      ),
      isTrue,
    );
  });

  test('Growth subtypes, combined photobionts and mixed strategies match', () {
    final mixed = _row(10, {
      'growthForm': 'Fol.u',
      'photobiont': 'Ch-Cy.h',
      'reproductiveStrategy': 'S-A.s',
      'substrata': 'Sax-Epiph',
    });
    for (final photo in ['Ch', 'Cy.h', 'Ch-Cy.h']) {
      for (final reproduction in ['S', 'A.s']) {
        final assessment = engine.assess(mixed, {
          ...choices,
          'photobiont': photo,
          'reproductiveStrategy': reproduction,
        });
        expect(assessment.differs, isFalse);
        expect(assessment.uncertain, isFalse);
      }
    }
    final mismatch = engine.assess(mixed, {...choices, 'substrata': 'Foliic'});
    expect(mismatch.criteria.last.label, 'Substrato non documentato');
  });

  test(
    'Unknown, unreviewed and stale cells never become negative evidence',
    () {
      final unknown = engine.assess(small.taxa.last, choices);
      expect(unknown.differs, isFalse);
      expect(unknown.uncertain, isTrue);
      final original = small.taxa.first;
      for (final cell in [
        CharacterCell(
          status: 'recorded',
          values: const ['Cr'],
          review: 'structured_source',
          evidence: original.cell('growthForm').evidence,
        ),
        CharacterCell(
          status: 'recorded',
          values: const ['Fol.b'],
          review: 'needs_review',
          evidence: original.cell('growthForm').evidence,
        ),
        const CharacterCell(
          status: 'recorded',
          values: ['Fol.b'],
          review: 'structured_source',
          evidence: [
            CharacterEvidence(
              field: 'ecologyCodes.growthForm',
              quote: 'not in source',
              rule: 'test',
            ),
          ],
        ),
        const CharacterCell(
          status: 'recorded',
          values: ['Bogus'],
          review: 'structured_source',
        ),
      ]) {
        final altered = MatrixTaxon(original.taxon, {
          ...original.cells,
          'growthForm': cell,
        });
        final result = engine.assess(altered, choices);
        expect(result.criteria.first.status, StructuredMatch.unknown);
        expect(result.differs, isFalse);
      }
    },
  );

  test('All unknown retains all taxa and ignores unapproved columns', () {
    final input = {
      for (final q in StructuredKey.questions) q.id: StructuredKey.unknown,
      'soredia': 'absent',
      'medulla_K': 'negative',
    };
    final result = engine.evaluate(small, input);
    expect(result.activeCriteria, 0);
    expect(result.matching, isEmpty);
    expect(result.different, isEmpty);
    expect(result.uncertain.length, 3);
    expect(
      engine.normalize({
        'growthForm': 'Fol',
        'photobiont': 'invalid',
        'substrata': 'Sax',
      }),
      {'growthForm': 'Fol'},
    );
    expect(engine.normalize({'substrata': 'Sax'}), isEmpty);
  });

  test(
    'Saved selections survive storage with photos, GPS and old paths',
    () async {
      final observation = _observation()
        ..identificationPath = IdentificationPath(
          keyId: StructuredKey.id,
          answers: const {},
          selections: choices,
          savedAt: DateTime.utc(2026, 10, 20),
        );
      final repository = ObservationRepository(factory: newIdbFactoryMemory());
      await repository.save(observation);
      final restored = (await repository.all()).single;
      expect(restored.identificationPath!.selections, choices);
      expect(restored.identificationPath!.answerCount, 4);
      expect(restored.photoBytes, orderedEquals([1, 2, 3]));
      expect(restored.latitude, observation.latitude);
      expect(restored.rank, IdentificationRank.undetermined);
      final old = IdentificationPath.fromMap({
        'keyId': 'macro-v1',
        'answers': {'crustose': 'a'},
        'savedAt': '2026-10-20T00:00:00Z',
      });
      expect(old!.answerCount, 1);
      expect(old.selections, isEmpty);
      expect(
        IdentificationPath.fromMap({
          'keyId': StructuredKey.id,
          'answers': {},
          'selections': {'growthForm': 'Fol', 'photobiont': 42},
          'savedAt': '2026-10-20T00:00:00Z',
        })!.selections,
        {'growthForm': 'Fol'},
      );
    },
  );

  Future<void> pick(WidgetTester tester, String id) async {
    final button = find.byKey(ValueKey('structured-choice-$id'));
    await tester.scrollUntilVisible(
      button,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Four questions, evidence, save and resume preserve identification',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final observation = _observation();
      final store = _Store();
      Widget page(Key key) => MaterialApp(
        theme: AppTheme.light,
        home: StructuredKeyPage(
          key: key,
          matrix: small,
          observation: observation,
          store: store,
        ),
      );
      await tester.pumpWidget(page(const ValueKey('first')));
      await tester.pumpAndSettle();
      for (final choice in choices.values) {
        await pick(tester, choice);
      }
      expect(find.text('Taxa da verificare'), findsOneWidget);
      expect(
        find.text(
          '1 profilo corrispondente · 1 con dati insufficienti · 1 con differenze',
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Confronto dei 4 caratteri').first);
      await tester.tap(find.text('Confronto dei 4 caratteri').first);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Fonte ecologyCodes.substrata: “Epiph-Lign”'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('save-structured-path')));
      await tester.pumpAndSettle();
      expect(observation.identificationPath!.selections, choices);
      expect(store.saved!.taxonName, isNull);
      expect(store.saved!.rank, IdentificationRank.undetermined);
      await tester.pumpWidget(page(const ValueKey('resume')));
      await tester.pumpAndSettle();
      expect(find.text('Percorso completato · 4 risposte'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('save-structured-path')),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'Changing the first answer can be undone with all later answers',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final observation = _observation()
        ..identificationPath = IdentificationPath(
          keyId: StructuredKey.id,
          answers: const {},
          selections: choices,
          savedAt: DateTime.utc(2026, 10, 20),
        );
      await tester.pumpWidget(
        MaterialApp(
          home: StructuredKeyPage(
            matrix: small,
            observation: observation,
            store: _Store(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('structured-edit-growthForm')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Passaggio 1 di 4'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('structured-undo')));
      await tester.pumpAndSettle();
      expect(find.text('Percorso completato · 4 risposte'), findsOneWidget);
      expect(find.text('Risposte salvate nell’osservazione.'), findsOneWidget);
    },
  );

  testWidgets('Failed replacement leaves previous path and permits retry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final previous = IdentificationPath(
      keyId: 'macro-v1',
      answers: {'crustose': KeyAnswer.a},
      savedAt: DateTime.utc(2026, 10, 20),
    );
    final observation = _observation()..identificationPath = previous;
    final store = _Store()..fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: StructuredKeyPage(
          matrix: small,
          observation: observation,
          store: store,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await pick(tester, 'Fol');
    expect(find.textContaining('sostituirà l’ultimo percorso'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('save-structured-path')));
    await tester.pumpAndSettle();
    expect(observation.identificationPath, same(previous));
    expect(find.textContaining('Salvataggio non riuscito'), findsOneWidget);
    store.fail = false;
    await tester.tap(find.byKey(const ValueKey('save-structured-path')));
    await tester.pumpAndSettle();
    expect(observation.identificationPath!.selections, {'growthForm': 'Fol'});
  });

  testWidgets('Phone: all four steps and fixed save action fit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: StructuredKeyPage(
          matrix: small,
          observation: _observation(),
          store: _Store(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final choice in choices.values) {
      await pick(tester, choice);
    }
    expect(find.text('Taxa da verificare'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('save-structured-path')));
    await tester.pumpAndSettle();
    expect(find.text('Risposte salvate nell’osservazione.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Restart removes a saved structured path only after saving', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final previous = IdentificationPath(
      keyId: StructuredKey.id,
      answers: const {},
      selections: choices,
      savedAt: DateTime.utc(2026, 10, 20),
    );
    final observation = _observation()..identificationPath = previous;
    final store = _Store();
    await tester.pumpWidget(
      MaterialApp(
        home: StructuredKeyPage(
          matrix: small,
          observation: observation,
          store: store,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('structured-restart')));
    await tester.pumpAndSettle();
    expect(observation.identificationPath, same(previous));
    expect(find.text('Rimuovi percorso salvato'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('save-structured-path')));
    await tester.pumpAndSettle();
    expect(observation.identificationPath, isNull);
    expect(store.saved!.identificationPath, isNull);
    expect(store.saved!.photoBytes, orderedEquals([1, 2, 3]));
  });

  testWidgets('The matrix opens the guided key directly from the app bar', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CharacterMatrixPage(
          matrix: small,
          reviewRepository: CharacterReviewRepository(
            factory: newIdbFactoryMemory(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('matrix-start-structured-key')));
    await tester.pumpAndSettle();
    expect(find.text('Percorso guidato · 4 caratteri'), findsOneWidget);
    expect(find.textContaining('Passaggio 1 di 4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

MatrixTaxon _row(int id, Map<String, String> codes) {
  final taxon = ItalicTaxon(
    scientificName: 'Example species $id',
    italicId: id,
    ecologyCodes: codes,
  );
  return MatrixTaxon(taxon, {
    for (final entry in codes.entries)
      entry.key: CharacterCell(
        status: 'recorded',
        review: 'structured_source',
        values: entry.key == 'substrata'
            ? entry.value.split('-')
            : [entry.value],
        evidence: [
          CharacterEvidence(
            field: 'ecologyCodes.${entry.key}',
            quote: entry.value,
            rule: 'structured-code-v1',
          ),
        ],
      ),
  });
}

Observation _observation() => Observation(
  id: 'structured-test',
  createdAt: DateTime.utc(2026, 10, 20),
  latitude: 45,
  longitude: 10,
  horizontalAccuracy: 5,
  photoBytes: Uint8List.fromList([1, 2, 3]),
);

class _Store extends AppStore {
  _Store() : super(ObservationRepository(factory: newIdbFactoryMemory()));
  bool fail = false;
  Observation? saved;
  @override
  Future<void> save(Observation observation) async {
    if (fail) throw StateError('Simulated failure');
    saved = observation;
  }
}
