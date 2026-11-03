import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:italicapp/app_store.dart';
import 'package:italicapp/data/character_matrix_repository.dart';
import 'package:italicapp/data/italic_api_traits_repository.dart';
import 'package:italicapp/data/observation_repository.dart';
import 'package:italicapp/models/observation.dart';
import 'package:italicapp/data/italic_reference_repository.dart';
import 'package:italicapp/pages/general_keys_page.dart';
import 'package:italicapp/pages/reconstructed_key_page.dart';
import 'package:italicapp/services/reconstructed_key.dart';
import 'package:italicapp/services/key_prefilter.dart';

void main() {
  late Map raw;
  late List<ItalicTaxon> reference;
  late ReconstructedKey key;
  late CharacterMatrix matrix;
  late ApiTraitsMatrix api;
  setUpAll(() {
    raw =
        jsonDecode(File(ReconstructedKey.generalAsset).readAsStringSync())
            as Map;
    reference =
        (jsonDecode(
                  File(
                    'assets/italic/italic_checklist.json',
                  ).readAsStringSync(),
                )['taxa']
                as List)
            .cast<Map>()
            .map((r) => ItalicTaxon.fromMap(Map<String, dynamic>.from(r)))
            .toList();
    key = ReconstructedKey.fromMap(raw, reference);
    matrix = CharacterMatrix.fromMap(
      jsonDecode(File(CharacterMatrixRepository.asset).readAsStringSync())
          as Map,
      reference,
    );
    api = ApiTraitsMatrix.fromMap(
      jsonDecode(File(ItalicApiTraitsRepository.asset).readAsStringSync())
          as Map,
      reference,
    );
  });
  Map changed() => jsonDecode(jsonEncode(raw)) as Map;

  test(
    'Complete checklist coverage is partitioned; extra and unresolved endpoints survive',
    () {
      expect(key.catalog.length, 3588);
      expect(key.coveredLocal, 3557);
      expect(key.unrepresented.length, 31);
      expect(key.extraTaxa.length, 5);
      expect(key.candidates(key.root).length, 3562);
      expect(key.unresolved(key.root).length, 5);
      expect(key.couplets, 4954);
      expect(key.occurrences, 4950);
      expect(key.aliases.length, 3);
      expect(key.nodes['lead_2449']!.terminal, isTrue);
      expect(key.nodes['lead_2449']!.taxonId, isNull);
      expect(key.pathCountFor(3064), 0);
      expect(key.associatedKeys[2863]!.single.url.host, 'dryades.units.it');
    },
  );

  test(
    'Every one of the 4950 terminal paths reaches the exact source occurrence',
    () {
      var count = 0;
      for (final id in key.taxa.keys) {
        final paths = key.pathsFor(id);
        expect(paths, isNotEmpty);
        for (final path in paths) {
          final input = {for (final s in path) s.node.id: s.choice.target};
          final leaf = key.current(input);
          expect(leaf.taxonId, id);
          expect(leaf.terminal, isTrue);
          count++;
        }
      }
      expect(count, 4950);
    },
  );

  test(
    'Genus pruning retains outer branch labels, duplicate occurrences and official source links',
    () {
      final scoped = key.forGenus('Physcia');
      expect(scoped.coveredLocal, 22);
      expect(scoped.occurrences, 25);
      expect(scoped.couplets, 24);
      expect(
        scoped.nodes[scoped.root]!.choices.first.label,
        'Thallus without soredia or isidia',
      );
      expect(scoped.normalize({}), {'_genus': 'Physcia'});
      for (final id in scoped.taxa.keys) {
        for (final path in scoped.pathsFor(id)) {
          final input = {for (final s in path) s.node.id: s.choice.target};
          expect(scoped.current(input).taxonId, id);
        }
      }
      expect(
        scoped.sourceFor(scoped.nodes[scoped.root]!).path,
        contains('/full/nodes/'),
      );
      expect(() => key.forGenus('Lichenothelia'), throwsFormatException);
      final cladonia = key.forGenus('Cladonia');
      expect(cladonia.unresolved(cladonia.root), contains('lead_2449'));
    },
  );

  test(
    'Peltigera covers every local taxon and each source occurrence reaches its species',
    () {
      final scoped = key.forGenus('Peltigera');
      final expected = reference
          .where((t) => t.scientificName.split(' ').first == 'Peltigera')
          .map((t) => t.italicId)
          .toSet();
      expect(expected.length, 23);
      expect(scoped.taxa.keys.toSet(), expected);
      expect(scoped.unrepresented, isEmpty);
      expect(scoped.occurrences, 26);
      expect(scoped.couplets, 25);
      expect(scoped.unresolved(scoped.root), isEmpty);
      for (final id in scoped.taxa.keys) {
        final paths = scoped.pathsFor(id);
        expect(paths, isNotEmpty);
        for (final path in paths) {
          final input = {
            for (final step in path) step.node.id: step.choice.target,
          };
          expect(scoped.current(input).taxonId, id);
          expect(scoped.normalize(input)['_genus'], 'Peltigera');
          for (final step in path) {
            expect(
              key.nodes[step.node.id]!.choices.map((c) => c.label),
              contains(step.choice.label),
            );
            expect(
              scoped.sourceFor(step.node),
              key.sourceFor(key.nodes[step.node.id]!),
            );
          }
        }
      }
    },
  );

  test(
    'Unknown preserves unresolved continuations; terms do not become traits',
    () {
      final normalized = key.normalize({
        key.root: 'unknown',
        'bogus': 'selected',
      });
      expect(normalized, {key.root: 'unknown'});
      expect(key.unresolved(key.current(normalized).id).length, 5);
      final choice = ReconstructedChoice(
        'x',
        'Thallus without soredia or isidia-like lobules',
        {},
        '',
      );
      expect(
        choice.terms,
        containsAll([
          'Sorali / soredi',
          'Isidi / strutture isidioidi',
          'Tallo',
        ]),
      );
      expect(choice.bindings, isEmpty);
    },
  );

  test(
    'Wrong coverage, identities, cycles and foreign associated URLs reject snapshots',
    () {
      final count = changed();
      count['referenceCount'] = 1;
      expect(
        () => ReconstructedKey.fromMap(count, reference),
        throwsFormatException,
      );
      final name = changed();
      name['taxa'][0]['scientificName'] = 'Wrong name';
      expect(
        () => ReconstructedKey.fromMap(name, reference),
        throwsFormatException,
      );
      final cycle = changed();
      cycle['nodes'][0]['choices'][0]['target'] = cycle['root'];
      expect(
        () => ReconstructedKey.fromMap(cycle, reference),
        throwsFormatException,
      );
      final url = changed();
      final t = (url['unrepresentedTaxa'] as List).firstWhere(
        (t) => t['italicId'] == 2863,
      );
      t['associatedKeys'][0]['url'] = 'https://example.org';
      expect(
        () => ReconstructedKey.fromMap(url, reference),
        throwsFormatException,
      );
    },
  );

  testWidgets('Phone: search paths and missing taxa, and start a known genus', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: GeneralKeysPage(definition: key, matrix: matrix, apiMatrix: api),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('3557 su 3588 taxa locali con percorso'), findsOneWidget);
    expect(find.text('Caratteri del campione'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('prefilter-growthForm-null')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('prefilter-photobiont-null')),
      findsNothing,
    );
    final group = find.byKey(const ValueKey('binary-group-Tallo'));
    await tester.scrollUntilVisible(
      group,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(group);
    await tester.pumpAndSettle();
    await tester.tap(group);
    await tester.pumpAndSettle();
    final field = find.byKey(
      const ValueKey('prefilter-binary:growth_form_foliose'),
    );
    await tester.scrollUntilVisible(
      field,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(field);
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('prefilter-count')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final comparison = KeyPrefilter(key, matrix, {
      'binary:growth_form_foliose': '1',
    }, apiMatrix: api);
    expect(
      find.textContaining(
        '${comparison.coveredLocal} taxa locali con percorso dopo il confronto',
      ),
      findsOneWidget,
    );
    expect(comparison.coveredLocal, lessThan(key.coveredLocal));
    final fruticose = find.byKey(
      const ValueKey('prefilter-binary:growth_form_fruticose'),
    );
    await tester.scrollUntilVisible(
      fruticose,
      -180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(fruticose);
    await tester.pumpAndSettle();
    await tester.tap(fruticose);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('prefilter-count')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final switched = KeyPrefilter(key, matrix, {
      'binary:growth_form_fruticose': '1',
    }, apiMatrix: api);
    expect(
      find.textContaining(
        '${switched.coveredLocal} taxa locali con percorso dopo il confronto',
      ),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      find.text('Azzera caratteri del campione'),
      -100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Azzera caratteri del campione'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('general-species-search')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('general-species-search')),
      '3064',
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('general-taxon-3064')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('general-taxon-3064')));
    await tester.pumpAndSettle();
    expect(find.textContaining('non ha un percorso'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('general-species-search')),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('general-species-search')),
      '1717',
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('general-taxon-1717')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('general-taxon-1717')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('taxon-path-count')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('general-genus-input')),
      -250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('general-genus-input')),
      'Physcia',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Physcia').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('general-start')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('general-start')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('general-start')));
    await tester.pumpAndSettle();
    expect(find.byType(ReconstructedKeyPage), findsOneWidget);
    expect(find.text('22 taxa nel ramo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'A scoped general path survives saving and restart without assigning a species',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final obs = Observation(
        id: 'general-test',
        createdAt: DateTime.utc(2026, 11, 2),
        latitude: 45,
        longitude: 10,
        horizontalAccuracy: 4,
        photoBytes: Uint8List.fromList([1, 2, 3]),
      );
      final store = _GeneralStore();
      await tester.pumpWidget(
        MaterialApp(
          home: ReconstructedKeyPage(
            definition: key,
            general: true,
            genus: 'Physcia',
            preFilters: const {'growthForm': 'Fol'},
            matrix: matrix,
            startFresh: true,
            observation: obs,
            store: store,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scoped = key.forGenus('Physcia');
      final comparison = KeyPrefilter(scoped, matrix, {'growthForm': 'Fol'});
      final filtered = scoped.filtered(comparison.eligible, comparison.filters);
      for (final step in filtered.pathsFor(1717).single) {
        final target = find.byKey(
          ValueKey('reconstructed-choice-${step.choice.target}'),
        );
        await tester.scrollUntilVisible(
          target,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey('reconstructed-save')));
      await tester.pumpAndSettle();
      expect(
        store.saved!.identificationPath!.keyId,
        ReconstructedKey.generalId,
      );
      expect(store.saved!.identificationPath!.selections['_genus'], 'Physcia');
      expect(
        store.saved!.identificationPath!.selections['_trait:growthForm'],
        'Fol',
      );
      expect(store.saved!.photoBytes, [1, 2, 3]);
      expect(store.saved!.taxonName, isNull);
      final reopened = Observation.fromMap(store.saved!.toMap());
      await tester.pumpWidget(
        MaterialApp(
          home: ReconstructedKeyPage(
            key: const ValueKey('resumed-general'),
            definition: key,
            matrix: matrix,
            general: true,
            observation: reopened,
            store: store,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Physcia adscendens H. Olivier'), findsOneWidget);
      expect(reopened.latitude, 45);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('An unresolved endpoint never produces a species result', (
    tester,
  ) async {
    // Reach the group through its actual source path by selecting the target at each ancestor.
    await tester.pumpWidget(
      MaterialApp(home: ReconstructedKeyPage(definition: key, general: true)),
    );
    await tester.pumpAndSettle();
    final parents = {
      for (final n in key.nodes.values)
        for (final c in n.choices) c.target: ReconstructedStep(n, c),
    };
    final reverse = <ReconstructedStep>[];
    var current = 'lead_2449';
    while (parents[current] != null) {
      final step = parents[current]!;
      reverse.add(step);
      current = step.node.id;
    }
    for (final step in reverse.reversed) {
      final target = find.byKey(
        ValueKey('reconstructed-choice-${step.choice.target}'),
      );
      await tester.scrollUntilVisible(
        target,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
    }
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('reconstructed-unresolved')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Cladonia coccifera-group'), findsOneWidget);
    expect(find.byKey(const ValueKey('reconstructed-result')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _GeneralStore extends AppStore {
  _GeneralStore()
    : super(ObservationRepository(factory: newIdbFactoryMemory()));
  Observation? saved;
  @override
  Future<void> save(Observation observation) async {
    saved = observation;
  }
}
