import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:italicapp/app_store.dart';
import 'package:italicapp/data/italic_reference_repository.dart';
import 'package:italicapp/data/observation_repository.dart';
import 'package:italicapp/models/identification_path.dart';
import 'package:italicapp/models/observation.dart';
import 'package:italicapp/pages/reconstructed_key_page.dart';
import 'package:italicapp/services/reconstructed_key.dart';

void main() {
  late Map raw;
  late ReconstructedKey key;
  late List<ItalicTaxon> reference;
  setUpAll(() {
    raw = jsonDecode(File(ReconstructedKey.asset).readAsStringSync()) as Map;
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
  });
  Map changed() => jsonDecode(jsonEncode(raw)) as Map;

  test(
    '22 taxa, 24 couplets and 25 distinct terminal occurrences preserve every source path',
    () {
      expect(key.taxa.length, 22);
      expect(key.couplets, 24);
      expect(key.occurrences, 25);
      expect(key.candidates(key.root).length, 22);
      final found = <int, int>{};
      for (final p in (raw['paths'] as List).cast<Map>()) {
        final input = {
          for (final s in (p['steps'] as List).cast<Map>())
            s['node'] as String: s['target'] as String,
        };
        final node = key.current(input);
        expect(node.terminal, isTrue);
        expect(node.id, p['occurrenceId']);
        expect(node.taxonId, p['taxonId']);
        expect(key.candidates(node.id), {p['taxonId']});
        found.update(node.taxonId!, (n) => n + 1, ifAbsent: () => 1);
      }
      expect(found[1728], 2);
      expect(found[1726], 2);
      expect(found[1721], 2);
      expect(key.unavailableRecords, ['4184']);
    },
  );

  test(
    'Adscendens and tenella split by soralia; composite leads do not invent traits',
    () {
      final input = {
        'lead_1504': 'lead_1676',
        'lead_1676': 'lead_1820',
        'lead_1820': 'lead_1846',
      };
      expect(key.candidates(key.current(input).id), {1717, 1735});
      expect(key.current({...input, 'lead_1846': 'lead_1847'}).taxonId, 1717);
      expect(key.current({...input, 'lead_1846': 'lead_1848'}).taxonId, 1735);
      expect(
        key.sourceFor(key.current(input)).path,
        endsWith('/nodes/14/interactive'),
      );
      expect(key.nodes[key.root]!.choices.last.bindings, isEmpty);
      expect(key.nodes['lead_1676']!.choices.last.bindings, {
        'soredia': 'present',
      });
    },
  );

  test(
    'Unknown preserves both branches and normalization truncates invalid or stale answers',
    () {
      final input = {'lead_1504': 'unknown', 'lead_1846': 'lead_1847'};
      expect(key.normalize(input), {'lead_1504': 'unknown'});
      expect(key.candidates(key.current(input).id).length, 22);
      expect(key.normalize({'lead_1504': 'bogus'}), isEmpty);
      final terminal = {
        'lead_1504': 'lead_1676',
        'lead_1676': 'lead_1820',
        'lead_1820': 'lead_1846',
        'lead_1846': 'lead_1847',
        'lead_1847': 'anything',
      };
      expect(key.normalize(terminal).length, 4);
    },
  );

  test(
    'Cycle, incomplete branches, renamed taxa and unsupported bindings reject the asset',
    () {
      final cycle = changed();
      cycle['nodes'][0]['choices'][0]['target'] = cycle['root'];
      expect(
        () => ReconstructedKey.fromMap(cycle, reference),
        throwsFormatException,
      );
      final incomplete = changed();
      (incomplete['nodes'][0]['choices'] as List).removeLast();
      expect(
        () => ReconstructedKey.fromMap(incomplete, reference),
        throwsFormatException,
      );
      final renamed = changed();
      renamed['taxa'][0]['scientificName'] = 'changed';
      expect(
        () => ReconstructedKey.fromMap(renamed, reference),
        throwsFormatException,
      );
      final unknown = changed();
      unknown['nodes'][0]['choices'][0]['bindings'] = {'soredia': 'invented'};
      expect(
        () => ReconstructedKey.fromMap(unknown, reference),
        throwsFormatException,
      );
    },
  );

  testWidgets(
    'Phone: complete local route, unknown, undo, save and resume without assigning species',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final obs = Observation(
        id: 'test',
        createdAt: DateTime.utc(2026, 11, 2),
        latitude: 45,
        longitude: 10,
        horizontalAccuracy: 4,
        photoBytes: Uint8List.fromList([1, 2, 3]),
      );
      final store = _Store();
      Widget page(String id) => MaterialApp(
        home: ReconstructedKeyPage(
          key: ValueKey(id),
          definition: key,
          observation: obs,
          store: store,
        ),
      );
      await tester.pumpWidget(page('first'));
      await tester.pumpAndSettle();
      Future<void> tap(Key target) async {
        await tester.scrollUntilVisible(
          find.byKey(target),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(target));
        await tester.tap(find.byKey(target));
        await tester.pumpAndSettle();
      }

      await tap(const ValueKey('reconstructed-unknown'));
      expect(find.text('22 taxa possibili'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('reconstructed-undo')));
      await tester.pumpAndSettle();
      for (final target in [
        'lead_1676',
        'lead_1820',
        'lead_1846',
        'lead_1847',
      ]) {
        await tap(ValueKey('reconstructed-choice-$target'));
      }
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('reconstructed-result')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Physcia adscendens H. Olivier'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('reconstructed-save')));
      await tester.pumpAndSettle();
      expect(obs.identificationPath!.keyId, ReconstructedKey.id);
      expect(obs.identificationPath!.selections.length, 4);
      expect(store.saved!.taxonName, isNull);
      expect(store.saved!.latitude, 45);
      expect(store.saved!.photoBytes, [1, 2, 3]);
      await tester.pumpWidget(page('resumed'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('reconstructed-result')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.byKey(const ValueKey('reconstructed-result')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('A failed save preserves the previous path and allows retry', (
    tester,
  ) async {
    final previous = IdentificationPath(
      keyId: 'old',
      answers: const {},
      savedAt: DateTime.utc(2026, 11, 1),
    );
    final obs = Observation(
      id: 'test',
      createdAt: DateTime.utc(2026, 11, 2),
      latitude: 45,
      longitude: 10,
      horizontalAccuracy: 4,
    )..identificationPath = previous;
    final store = _Store()..fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: ReconstructedKeyPage(
          definition: key,
          observation: obs,
          store: store,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('reconstructed-unknown')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reconstructed-unknown')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reconstructed-save')));
    await tester.pumpAndSettle();
    expect(obs.identificationPath, same(previous));
    store.fail = false;
    await tester.tap(find.byKey(const ValueKey('reconstructed-save')));
    await tester.pumpAndSettle();
    expect(obs.identificationPath!.keyId, ReconstructedKey.id);
  });
}

class _Store extends AppStore {
  _Store() : super(ObservationRepository(factory: newIdbFactoryMemory()));
  bool fail = false;
  Observation? saved;
  @override
  Future<void> save(Observation observation) async {
    if (fail) throw StateError('test');
    saved = observation;
  }
}
