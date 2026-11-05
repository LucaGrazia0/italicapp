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
import 'package:italicapp/widgets/candidate_selection.dart';
import 'package:italicapp/services/reconstructed_key.dart';

void main() {
  late ReconstructedKey key;
  setUpAll(() {
    final reference =
        (jsonDecode(
                  File(
                    'assets/italic/italic_checklist.json',
                  ).readAsStringSync(),
                )['taxa']
                as List)
            .cast<Map>()
            .map((m) => ItalicTaxon.fromMap(Map<String, dynamic>.from(m)))
            .toList();
    key = ReconstructedKey.fromMap(
      jsonDecode(File(ReconstructedKey.asset).readAsStringSync()) as Map,
      reference,
    );
  });
  Observation observation() => Observation(
    id: 'candidate-test',
    createdAt: DateTime.utc(2026, 11, 2),
    latitude: 45.1,
    longitude: 11.2,
    horizontalAccuracy: 3,
    gpsAltitude: 400,
    altitudeAccuracy: 5,
    substrate: 'Corteccia',
    notes: 'Nota originale',
    photoName: 'foto.jpg',
    photoBytes: Uint8List.fromList([1, 2, 3]),
  );
  Future<void> top(WidgetTester tester) async {
    tester.widget<ListView>(find.byType(ListView).first).controller!.jumpTo(0);
    await tester.pumpAndSettle();
  }

  Future<void> showList(WidgetTester tester) async {
    await top(tester);
    final shortcut = find.text('Vedi le specie rimaste');
    await tester.scrollUntilVisible(
      shortcut,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(shortcut);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('remaining-candidates-count')),
      findsOneWidget,
    );
  }

  testWidgets(
    'Remaining species update on each branch and Back; unknown preserves both and manual choice persists the full observation',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final original = observation();
      final store = _SelectionStore();
      await tester.pumpWidget(
        MaterialApp(
          home: ReconstructedKeyPage(
            definition: key,
            observation: original,
            store: store,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await showList(tester);
      expect(find.text('Specie rimaste (22)'), findsOneWidget);
      expect(original.taxonName, isNull);
      for (final target in ['lead_1676', 'lead_1820', 'lead_1846']) {
        await top(tester);
        final button = find.byKey(ValueKey('reconstructed-choice-$target'));
        await tester.scrollUntilVisible(
          button,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
      }
      await showList(tester);
      expect(find.text('Specie rimaste (2)'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('remaining-candidate-1717')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('remaining-candidate-1735')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('remaining-candidate-1718')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('reconstructed-undo')));
      await tester.pumpAndSettle();
      await showList(tester);
      expect(find.text('Specie rimaste (2)'), findsNothing);
      await top(tester);
      final forward = find.byKey(
        const ValueKey('reconstructed-choice-lead_1846'),
      );
      await tester.scrollUntilVisible(
        forward,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(forward);
      await tester.pumpAndSettle();
      final unknown = find.byKey(const ValueKey('reconstructed-unknown'));
      await tester.scrollUntilVisible(
        unknown,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(unknown);
      await tester.pumpAndSettle();
      await showList(tester);
      expect(find.text('Specie rimaste (2)'), findsOneWidget);
      final choose = find.byKey(const ValueKey('choose-candidate-1717'));
      await tester.ensureVisible(choose);
      await tester.tap(choose);
      await tester.pumpAndSettle();
      final saved = store.saved!;
      expect(saved.taxonName, 'Physcia adscendens H. Olivier');
      expect(saved.rank, IdentificationRank.species);
      expect(original.taxonName, saved.taxonName);
      expect(saved.identificationPath!.selections['lead_1846'], 'unknown');
      expect(saved.photoBytes, [1, 2, 3]);
      expect(saved.photoName, 'foto.jpg');
      expect(saved.notes, 'Nota originale');
      expect(saved.latitude, 45.1);
      expect(saved.longitude, 11.2);
      expect(saved.gpsAltitude, 400);
      expect(saved.altitudeAccuracy, 5);
      expect(saved.substrate, 'Corteccia');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Failed candidate save keeps the previous name and path; retry works',
    (tester) async {
      final original = observation()
        ..rank = IdentificationRank.genus
        ..taxonName = 'Physcia';
      final previous = IdentificationPath(
        keyId: 'previous',
        answers: const {},
        savedAt: DateTime.utc(2026, 11, 1),
      );
      original.identificationPath = previous;
      final store = _SelectionStore()..fail = true;
      await tester.pumpWidget(
        MaterialApp(
          home: ReconstructedKeyPage(
            definition: key,
            observation: original,
            store: store,
            startFresh: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await showList(tester);
      await tester.enterText(
        find.byKey(const ValueKey('remaining-candidates-search')),
        '1717',
      );
      await tester.pumpAndSettle();
      final choose = find.byKey(const ValueKey('choose-candidate-1717'));
      await tester.ensureVisible(choose);
      await tester.tap(choose);
      await tester.pumpAndSettle();
      expect(original.taxonName, 'Physcia');
      expect(original.rank, IdentificationRank.genus);
      expect(original.identificationPath, same(previous));
      expect(
        find.textContaining('Identificazione non salvata.'),
        findsOneWidget,
      );
      store.fail = false;
      await tester.tap(choose);
      await tester.pumpAndSettle();
      expect(original.taxonName, 'Physcia adscendens H. Olivier');
      expect(store.observations.single.taxonName, original.taxonName);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Free mode shows remaining candidates without diary selection buttons',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: ReconstructedKeyPage(definition: key)),
      );
      await tester.pumpAndSettle();
      await showList(tester);
      expect(find.text('Specie rimaste (22)'), findsOneWidget);
      expect(find.byType(CandidateSelectionButton), findsNothing);
    },
  );
}

class _SelectionStore extends AppStore {
  _SelectionStore()
    : super(ObservationRepository(factory: newIdbFactoryMemory()));
  bool fail = false;
  Observation? saved;
  @override
  Future<void> save(Observation observation) async {
    if (fail) throw StateError('Simulated failed write');
    saved = Observation.fromMap(observation.toMap());
    observations = [saved!];
    notifyListeners();
  }
}
