import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:italicapp/app_store.dart';
import 'package:italicapp/data/italic_reference_repository.dart';
import 'package:italicapp/data/observation_repository.dart';
import 'package:italicapp/models/observation.dart';
import 'package:italicapp/services/field_achievements.dart';
import 'package:italicapp/theme/app_theme.dart';
import 'package:italicapp/widgets/diary_achievements.dart';

final taxa = [
  const ItalicTaxon(
    scientificName: 'Physcia aipolia (Ehrh. ex Humb.) Fürnr.',
    italicId: 1717,
    synonyms: ['Lichen aipolius Ehrh. ex Humb.'],
  ),
  const ItalicTaxon(scientificName: 'Physcia aipolia var. test', italicId: 999),
  const ItalicTaxon(
    scientificName: 'Physcia adscendens H. Olivier',
    italicId: 1718,
  ),
  for (var i = 0; i < 100; i++)
    ItalicTaxon(
      scientificName:
          'Testus ${String.fromCharCode(97 + i ~/ 26)}${String.fromCharCode(97 + i % 26)}',
      italicId: 30000 + i,
    ),
];
Observation record(
  String id,
  String? name, {
  IdentificationRank rank = IdentificationRank.species,
}) => Observation(
  id: id,
  createdAt: DateTime(2026, 11, 4),
  rank: rank,
  taxonName: name,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FieldAchievementIndex index;
  setUp(() => index = FieldAchievementIndex(taxa));
  test(
    'Every exact threshold unlocks once; maximum completion has no next goal',
    () {
      expect(index.progress([]).unlockedCount, 0);
      for (var i = 0; i < fieldAchievements.length; i++) {
        final a = fieldAchievements[i];
        expect(FieldAchievementProgress(a.target - 1).unlocked(a), false);
        final progress = FieldAchievementProgress(a.target);
        expect(progress.unlocked(a), true);
        expect(progress.unlockedCount, i + 1);
        expect(progress.fraction(a), 1);
        expect(progress.remaining(a), 0);
      }
      expect(const FieldAchievementProgress(1000).next, isNull);
      expect(const FieldAchievementProgress(1001).unlockedCount, 6);
    },
  );
  test(
    'Photos, authorship variants, synonyms and varieties count as one accepted species',
    () {
      final observations = [
        record('1', 'Physcia aipolia (Ehrh. ex Humb.) Fürnr.'),
        record('2', '  PHYSCIA   AIPOLIA '),
        record('3', 'Lichen aipolius Ehrh. ex Humb.'),
        record('4', 'Physcia aipolia var. test'),
      ];
      expect(index.progress(observations).speciesCount, 1);
      observations.add(record('5', 'Physcia adscendens'));
      expect(index.progress(observations).speciesCount, 2);
    },
  );
  test(
    'Genus, family, unconfirmed candidates, unknown names and uncertain identifications do not count',
    () {
      for (final rank in IdentificationRank.values.where(
        (r) => r != IdentificationRank.species,
      )) {
        expect(
          index.speciesKey(record('a', 'Physcia aipolia', rank: rank)),
          isNull,
        );
      }
      for (final name in [
        null,
        '',
        'Physcia',
        'Physcia sp.',
        'Physcia cf. aipolia',
        'Physcia cfr. aipolia',
        'Physcia aff. aipolia',
        'Physcia unknown',
        'Unknown taxon',
      ]) {
        expect(
          index.speciesKey(record('a', name)),
          isNull,
          reason: '$name should not unlock badges',
        );
      }
    },
  );
  test('Latin names with diacritics count as recognized species', () {
    final names = FieldAchievementIndex([
      const ItalicTaxon(scientificName: 'Candelariella kuusamoënsis Räsänen'),
    ]);
    expect(
      names.progress([record('a', 'Candelariella kuusamoënsis')]).speciesCount,
      1,
    );
  });
  test('An ambiguous synonym cannot create a false species', () {
    final ambiguous = FieldAchievementIndex([
      const ItalicTaxon(
        scientificName: 'Genus alpha',
        synonyms: ['Oldus ambiguous'],
      ),
      const ItalicTaxon(
        scientificName: 'Genus beta',
        synonyms: ['Oldus ambiguous'],
      ),
    ]);
    expect(ambiguous.speciesKey(record('a', 'Oldus ambiguous')), isNull);
    expect(
      ambiguous.progress([
        record('b', 'Genus alpha'),
        record('c', 'Genus beta'),
      ]).speciesCount,
      2,
    );
  });
  test(
    'Saved determinations restore achievements offline; corrections and deletion follow the diary',
    () async {
      final repository = ObservationRepository(factory: newIdbFactoryMemory());
      final store = AppStore(repository);
      await store.init();
      for (var i = 0; i < 5; i++) {
        await store.save(record('$i', taxa[i + 3].scientificName));
      }
      expect(index.progress(store.observations).unlockedCount, 1);
      final reopened = AppStore(
        ObservationRepository(factory: repository.factory),
      );
      await reopened.init();
      expect(index.progress(reopened.observations).speciesCount, 5);
      await reopened.save(record('4', taxa[3].scientificName));
      expect(index.progress(reopened.observations).speciesCount, 4);
      await reopened.delete(
        reopened.observations.singleWhere((o) => o.id == '0'),
      );
      expect(index.progress(reopened.observations).speciesCount, 4);
      await reopened.delete(
        reopened.observations.singleWhere((o) => o.id == '4'),
      );
      expect(index.progress(reopened.observations).speciesCount, 3);
      await repository.close();
      await reopened.repository.close();
    },
  );
  testWidgets(
    'Phone summary updates after a determination and opens locked and unlocked badges',
    (tester) async {
      tester.view.physicalSize = const Size(375, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = AppStore(
        ObservationRepository(factory: newIdbFactoryMemory()),
      );
      await tester.runAsync(store.init);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ListView(
              children: [
                DiaryAchievements(store: store, loadIndex: () async => index),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Traguardi · 0/6'), findsOneWidget);
      await tester.runAsync(() => store.save(record('1', 'Physcia aipolia')));
      await tester.pumpAndSettle();
      expect(find.text('Traguardi · 1/6'), findsOneWidget);
      await tester.runAsync(() => store.save(record('2', 'Physcia aipolia')));
      await tester.pumpAndSettle();
      expect(find.text('Traguardi · 1/6'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('open-achievements')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('achievement-page-count')))
            .data,
        '1 specie diversa',
      );
      expect(find.text('Sbloccato'), findsOneWidget);
      expect(find.text('Mancano 9 specie'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('achievement-1')));
      await tester.pumpAndSettle();
      expect(find.text('Federico Cesi'), findsOneWidget);
      expect(find.text('Fonti e letture'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('close-achievement')));
      await tester.pumpAndSettle();
      await tester.runAsync(() => store.delete(store.observations.first));
      await tester.pumpAndSettle();
      expect(find.text('Sbloccato'), findsOneWidget);
      await tester.runAsync(() => store.delete(store.observations.first));
      await tester.pumpAndSettle();
      expect(find.text('Sbloccato'), findsNothing);
      expect(find.text('Manca 1 specie'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(store.repository.close);
    },
  );
  testWidgets(
    'Missing checklist can be retried without hiding the diary; large text fits on a narrow phone',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = AppStore(
        ObservationRepository(factory: newIdbFactoryMemory()),
      );
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: Scaffold(
              body: ListView(
                children: [
                  const Text('Diario disponibile'),
                  DiaryAchievements(
                    store: store,
                    loadIndex: () async {
                      if (attempts++ == 0) throw StateError('file unavailable');
                      return index;
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Diario disponibile'), findsOneWidget);
      await tester.tap(find.text('Traguardi · Riprova'));
      await tester.pumpAndSettle();
      expect(find.text('Traguardi · 0/6'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('open-achievements')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('achievement-100')),
        400,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
