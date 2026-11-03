import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:italicapp/app_store.dart';
import 'package:italicapp/data/character_matrix_repository.dart';
import 'package:italicapp/data/character_review_repository.dart';
import 'package:italicapp/data/italic_api_traits_repository.dart';
import 'package:italicapp/data/italic_reference_repository.dart';
import 'package:italicapp/data/observation_repository.dart';
import 'package:italicapp/models/character_review.dart';
import 'package:italicapp/models/observation.dart';
import 'package:italicapp/pages/species_key_page.dart';
import 'package:italicapp/services/italic_keymaker_client.dart';
import 'package:italicapp/services/species_key_engine.dart';

const uuid = 'dc7ee764-79a3-11ef-aabf-000c2978584b';
const officialUrl =
    'https://italic.units.it/key-maker/$uuid/nodes/1/interactive';
SpeciesQuestion q(String id) =>
    SpeciesKeyEngine.allQuestions.singleWhere((q) => q.id == id);

void main() {
  late CharacterMatrix matrix;
  late ApiTraitsMatrix api;
  late MatrixTaxon aipolia;
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
    matrix = CharacterMatrix.fromMap(
      jsonDecode(
        File('assets/italic/character_matrix_v2.json').readAsStringSync(),
      ),
      taxa,
    );
    api = ApiTraitsMatrix.fromMap(
      jsonDecode(
        File('assets/italic/api_traits_matrix_v2.json').readAsStringSync(),
      ),
      taxa,
    );
    aipolia = matrix.taxa.singleWhere((r) => r.taxon.italicId == 1718);
  });

  test(
    'All 3588 stay in the partition; missing values survive and genus is explicit',
    () {
      final e = SpeciesKeyEngine(matrix, api: api);
      expect(e.evaluate({}).uncertain.length, 3588);
      expect(e.next({}, e.evaluate({}))!.id, 'growthForm');
      for (final selections in <Map<String, String>>[
        {'growthForm': 'Fol'},
        {'growthForm': 'unknown'},
        {'api_spore_cells': 'two'},
        {'_genus': 'Physcia'},
      ]) {
        final result = e.evaluate(selections);
        expect(
          result.matching.length +
              result.uncertain.length +
              result.different.length,
          selections.containsKey('_genus') ? 22 : 3588,
        );
        if (selections.containsValue('unknown')) {
          expect(result.possible.length, 3588);
        }
      }
      expect(e.normalize({'_genus': 'Phys', 'bogus': 'x'}), isEmpty);
      expect(
        e
            .evaluate({'_genus': 'Physcia'})
            .possible
            .every((c) => c.row.taxon.scientificName.startsWith('Physcia ')),
        isTrue,
      );
      final empty = SpeciesKeyEngine(
        CharacterMatrix(matrix.characters, [aipolia]),
      );
      expect(empty.evaluate({'api_spore_cells': 'two'}).oneProfile, isFalse);
      expect(empty.evaluate({'api_spore_cells': 'two'}).uncertain.length, 1);
      expect(
        empty.available({}, empty.evaluate({})).any((q) => q.review != null),
        isTrue,
      );
      expect(
        e.available({}, e.evaluate({})).any((q) => q.review != null),
        isFalse,
      );
    },
  );

  test(
    'API multi-states, partial missing values, inapplicability and conflicts',
    () {
      SpeciesKeyEngine fixture(
        Map<String, int?> values, {
        bool stale = false,
        List<ApiTraitConflict> conflicts = const [],
      }) => SpeciesKeyEngine(
        CharacterMatrix(matrix.characters, [aipolia]),
        api: ApiTraitsMatrix([], [
          ApiTraitRow(
            taxon: aipolia.taxon,
            values: values,
            sourceUrl: 'https://italic.units.it/api/v2/traits-pa/1718',
            retrievedAt: '2026-11-02',
            conflicts: conflicts,
            warning: '',
            schemaIssueCount: 0,
            descriptionChanged: stale,
          ),
        ]),
      );
      SpeciesMatch status(SpeciesKeyEngine e, String id, String value) =>
          e.criterion(aipolia, q(id), value).status;
      final multiple = fixture({
        'ascospores_pigmented': 1,
        'ascospores_hyaline': 1,
      });
      expect(
        status(multiple, 'api_spore_colour', 'pigmented'),
        SpeciesMatch.match,
      );
      expect(
        status(multiple, 'api_spore_colour', 'hyaline'),
        SpeciesMatch.match,
      );
      expect(
        status(
          fixture({'ascospores_pigmented': 1}),
          'api_spore_colour',
          'hyaline',
        ),
        SpeciesMatch.unknown,
      );
      expect(
        status(
          fixture({'ascospores_pigmented': 1, 'ascospores_hyaline': 0}),
          'api_spore_colour',
          'hyaline',
        ),
        SpeciesMatch.different,
      );
      expect(
        status(
          fixture({'ascocarps_apothecioid': 0, 'apothecia_lecanorine': 0}),
          'api_apothecia_type',
          'not_lecanorine',
        ),
        SpeciesMatch.unknown,
      );
      expect(
        status(
          fixture({'ascocarps_apothecioid': 1, 'apothecia_lecanorine': 0}),
          'api_apothecia_type',
          'not_lecanorine',
        ),
        SpeciesMatch.match,
      );
      expect(
        status(
          fixture({'ascospores_pigmented': 1}, stale: true),
          'api_spore_colour',
          'pigmented',
        ),
        SpeciesMatch.unknown,
      );
      expect(
        status(
          fixture(
            {'ascospores_pigmented': 1},
            conflicts: [
              const ApiTraitConflict('ascospores_pigmented', 'Conflict'),
            ],
          ),
          'api_spore_colour',
          'pigmented',
        ),
        SpeciesMatch.unknown,
      );
      expect(
        SpeciesKeyEngine.apiQuestions.any(
          (q) => q.id.contains('ascus') || q.id.contains('cortex'),
        ),
        isFalse,
      );
    },
  );

  test(
    'Latest manual review overrides API; drafts and stale reviews never fall back',
    () {
      final confirmed = CharacterReview.create(
        taxon: aipolia.taxon,
        characterId: 'apothecia_type',
        value: 'lecanorine',
        status: 'reviewed',
        reviewer: 'Test',
        quote: 'lecanorine',
      );
      SpeciesKeyEngine e(List<CharacterReview> reviews) =>
          SpeciesKeyEngine(matrix, api: api, registry: ReviewRegistry(reviews));
      expect(
        e([
          confirmed,
        ]).criterion(aipolia, q('api_apothecia_type'), 'lecanorine').status,
        SpeciesMatch.match,
      );
      expect(
        e([
          confirmed,
        ]).criterion(aipolia, q('api_ascocarp_form'), 'apothecioid').status,
        SpeciesMatch.match,
      );
      final draft = CharacterReview.create(
        taxon: aipolia.taxon,
        characterId: 'apothecia_type',
        value: 'unknown',
        status: 'draft',
        reviewer: 'Test',
        quote: '',
        previous: confirmed,
      );
      expect(
        e([
          confirmed,
          draft,
        ]).criterion(aipolia, q('api_apothecia_type'), 'lecanorine').status,
        SpeciesMatch.unknown,
      );
      final absence = CharacterReview.create(
        taxon: aipolia.taxon,
        characterId: 'soredia',
        value: 'absent',
        status: 'reviewed',
        reviewer: 'Test',
        quote: '',
      );
      expect(
        e([absence]).criterion(aipolia, q('review:soredia'), 'absent').status,
        SpeciesMatch.match,
      );
      expect(
        e([
          absence,
        ]).criterion(aipolia, q('review:soralia_shape'), 'hood').status,
        SpeciesMatch.unknown,
      );
      expect(
        e([]).criterion(aipolia, q('review:soredia'), 'absent').status,
        SpeciesMatch.unknown,
      );
      final stale = CharacterReview.create(
        taxon: ItalicTaxon(
          italicId: 1718,
          scientificName: aipolia.taxon.scientificName,
          description: 'old lecanorine',
        ),
        characterId: 'apothecia_type',
        value: 'lecanorine',
        status: 'reviewed',
        reviewer: 'Test',
        quote: 'lecanorine',
      );
      expect(
        e([
          stale,
        ]).criterion(aipolia, q('api_apothecia_type'), 'lecanorine').status,
        SpeciesMatch.unknown,
      );
    },
  );

  test(
    'Parent absences remove shape and position answers; microscopy dependencies',
    () {
      final e = SpeciesKeyEngine(matrix);
      final selections = e.normalize({
        'review:soredia': 'absent',
        'review:soralia_shape': 'hood',
        'review:soralia_position': 'terminal',
        'api_ascocarp_form': 'perithecioid',
        'api_apothecia_type': 'lecanorine',
        'api_spore_cells': 'one',
        'api_polarilocular': 'yes',
        'api_muriform': 'yes',
      });
      expect(
        selections.keys,
        unorderedEquals([
          'review:soredia',
          'api_ascocarp_form',
          'api_spore_cells',
        ]),
      );
      expect(e.next(selections, e.evaluate(selections)), isNotNull);
      final sterile = e.normalize({
        'review:apothecia_type': 'absent',
        'api_ascocarp_form': 'apothecioid',
        'api_apothecia_type': 'lecanorine',
        'api_lirelliform': 'yes',
      });
      expect(sterile, {'review:apothecia_type': 'absent'});
      expect(
        e.available(sterile, e.evaluate(sterile)).map((q) => q.id),
        isNot(contains('api_lirelliform')),
      );
    },
  );

  test(
    'Official client sends names only, deduplicates, validates URL, caches and ignores record count',
    () async {
      var calls = 0;
      final client = ItalicKeymakerClient(
        client: MockClient((request) async {
          calls++;
          expect(request.method, 'POST');
          expect(
            request.url.toString(),
            'https://italic.units.it/api/v2/keymaker',
          );
          expect(jsonDecode(request.body), [
            'Physcia aipolia',
            'Physcia albinea',
          ]);
          return http.Response(
            jsonEncode({
              'key_id': uuid,
              'link': officialUrl,
              'records': ['opaque'],
            }),
            200,
          );
        }),
      );
      addTearDown(client.close);
      final key = await client.generate([
        ' Physcia albinea ',
        'Physcia aipolia',
        'Physcia aipolia',
      ]);
      expect(key.names.length, 2);
      expect(key.url.toString(), officialUrl);
      expect(
        await client.generate(['Physcia aipolia', 'Physcia albinea']),
        same(key),
      );
      expect(calls, 1);
      await expectLater(client.generate(['single']), throwsFormatException);
      await expectLater(
        client.generate(List.generate(101, (i) => 'Taxon $i')),
        throwsFormatException,
      );
    },
  );

  test(
    'Official client rejects foreign, malformed and unsuccessful responses',
    () async {
      for (final response in [
        http.Response('busy', 429),
        http.Response('error', 503),
        http.Response('{}', 200),
        http.Response('invalid', 200),
        http.Response(
          jsonEncode({'key_id': uuid, 'link': 'https://example.org/key'}),
          200,
        ),
      ]) {
        final client = ItalicKeymakerClient(
          client: MockClient((_) async => response),
        );
        await expectLater(
          client.generate(['A', 'B']),
          throwsA(anyOf(isA<StateError>(), isA<FormatException>())),
        );
        client.close();
      }
    },
  );

  testWidgets(
    'Phone: scope, official names include unknowns, save, resume, undo and failed replacement',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final small = CharacterMatrix(matrix.characters, [
        aipolia,
        matrix.taxa.singleWhere((r) => r.taxon.italicId == 1717),
      ]);
      final observation = Observation(
        id: 'species-test',
        createdAt: DateTime.utc(2026, 11, 2),
        latitude: 45,
        longitude: 10,
        horizontalAccuracy: 5,
        photoBytes: Uint8List.fromList([1, 2, 3]),
      );
      final store = _Store();
      List<String>? sent;
      final client = ItalicKeymakerClient(
        client: MockClient((request) async {
          sent = (jsonDecode(request.body) as List).cast<String>();
          return http.Response(
            jsonEncode({'key_id': uuid, 'link': officialUrl}),
            200,
          );
        }),
      );
      addTearDown(client.close);
      Widget page(String key) => MaterialApp(
        home: SpeciesKeyPage(
          key: ValueKey(key),
          matrix: small,
          api: const ApiTraitsMatrix([], []),
          registry: ReviewRegistry([]),
          client: client,
          observation: observation,
          store: store,
        ),
      );
      await tester.pumpWidget(page('first'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('species-genus-input')),
        'Phys',
      );
      await tester.pumpAndSettle();
      expect(find.text('2 taxa possibili'), findsOneWidget);
      await tester.tap(find.text('Physcia').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('species-save')));
      await tester.pumpAndSettle();
      expect(observation.identificationPath!.selections, {'_genus': 'Physcia'});
      expect(store.saved!.latitude, 45);
      expect(store.saved!.photoBytes, [1, 2, 3]);
      expect(store.saved!.taxonName, isNull);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('species-generate')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('species-generate')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('species-generate')));
      await tester.pumpAndSettle();
      expect(
        sent,
        unorderedEquals(small.taxa.map((r) => r.taxon.scientificName)),
      );
      expect(sent!.length, 2);
      expect(
        find.byKey(const ValueKey('species-official-link')),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('species-restart')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('species-restart')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('species-official-link')), findsNothing);
      store.fail = true;
      await tester.tap(find.byKey(const ValueKey('species-save')));
      await tester.pumpAndSettle();
      expect(observation.identificationPath!.selections, {'_genus': 'Physcia'});
      await tester.tap(find.byKey(const ValueKey('species-undo')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('species-save')))
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(page('resumed'));
      await tester.pumpAndSettle();
      expect(find.text('Genere già riconosciuto: Physcia'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Adaptive choices, skipped answers, editing and undo preserve the branch',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final small = CharacterMatrix(matrix.characters, [
        aipolia,
        matrix.taxa.singleWhere((r) => r.taxon.italicId == 1717),
      ]);
      final engine = SpeciesKeyEngine(small);
      final first = engine.next({}, engine.evaluate({}))!;
      final single = first.choices.keys.firstWhere(
        (choice) => engine.evaluate({first.id: choice}).oneProfile,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SpeciesKeyPage(
            matrix: small,
            api: const ApiTraitsMatrix([], []),
            registry: ReviewRegistry([]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('species-question')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('species-skip')));
      await tester.pumpAndSettle();
      // Skipping a question does not remove either taxon.
      expect(find.text('2 taxa possibili'), findsOneWidget);
      while (find.byKey(const ValueKey('species-skip')).evaluate().isNotEmpty) {
        await tester.ensureVisible(find.byKey(const ValueKey('species-skip')));
        await tester.tap(find.byKey(const ValueKey('species-skip')));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.textContaining('Le tue risposte'));
      await tester.tap(find.textContaining('Le tue risposte'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Modifica').first);
      await tester.tap(find.text('Modifica').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('species-question')), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(ValueKey('species-choice-$single')),
      );
      await tester.tap(find.byKey(ValueKey('species-choice-$single')));
      await tester.pumpAndSettle();
      expect(find.text('1 taxon possibile'), findsOneWidget);
      expect(find.text('Un solo profilo compatibile nei dati'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('species-undo')));
      await tester.pumpAndSettle();
      expect(find.text('2 taxa possibili'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Unreadable reviews suspend API comparisons and show why', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SpeciesKeyPage(
          matrix: CharacterMatrix(matrix.characters, [aipolia]),
          api: api,
          reviewRepository: _Unreadable(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Revisioni locali non leggibili'),
      findsOneWidget,
    );
    final state = tester.state(find.byType(SpeciesKeyPage));
    expect(state.mounted, isTrue);
    expect(tester.takeException(), isNull);
  });
}

class _Store extends AppStore {
  _Store() : super(ObservationRepository(factory: newIdbFactoryMemory()));
  bool fail = false;
  Observation? saved;
  @override
  Future<void> save(Observation observation) async {
    if (fail) throw StateError('test failure');
    saved = observation;
  }
}

class _Unreadable extends CharacterReviewRepository {
  @override
  Future<List<CharacterReview>> all() async => throw StateError('test failure');
}
