import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:italicapp/app_store.dart';
import 'package:italicapp/data/italic_reference_repository.dart';
import 'package:italicapp/data/observation_repository.dart';
import 'package:italicapp/models/observation.dart';
import 'package:italicapp/pages/diary_page.dart';
import 'package:italicapp/pages/species_picker_page.dart';
import 'package:italicapp/services/manual_species.dart';
import 'observation_export_test.dart' show exampleObservation;

const taxa = [
  ItalicTaxon(
    scientificName: 'Physcia adscendens H. Olivier',
    italicId: 1717,
    synonyms: ['Lichen adscendens'],
  ),
  ItalicTaxon(scientificName: 'Physcia aipolia (Ehrh.) Fürnr.', italicId: 1718),
];

void main() {
  test(
    'A checklist choice preserves photo, coordinates, uncertainty, notes and key history',
    () {
      final original = exampleObservation().withMapPosition(
        45,
        11,
        uncertaintyInMeters: 25,
      );
      final before = original.toMap();
      final assigned = assignSpecies(original, taxa.first);
      final expected = Map.of(before)
        ..addAll({
          'taxonName': taxa.first.scientificName,
          'taxonItalicId': 1717,
          'rank': 'species',
          'identificationMethod': 'manual',
        });
      expect(assigned.toMap(), expected);
      expect(original.toMap(), before);
    },
  );

  for (final query in ['1717', 'Lichen adscendens']) {
    testWidgets('The offline list searches by ID or synonym: $query', (
      tester,
    ) async {
      ItalicTaxon? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async =>
                    chosen = await Navigator.push<ItalicTaxon>(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            SpeciesPickerPage(loadTaxa: () async => taxa),
                      ),
                    ),
                child: const Text('Scegli'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Scegli'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('species-picker-search')),
        query,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pick-species-1718')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('pick-species-1717')));
      await tester.pumpAndSettle();
      expect(chosen, same(taxa.first));
      expect(tester.takeException(), isNull);
    });
  }

  for (final fail in [false, true]) {
    testWidgets(
      'Assignment ${fail ? 'write failure preserves the old name' : 'saves the selected name'}',
      (tester) async {
        final store = _Store()..fail = fail;
        final original = exampleObservation();
        final before = original.toMap();
        Observation? result;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async =>
                      result = await chooseObservationSpecies(
                        context,
                        store: store,
                        observation: original,
                        loadTaxa: () async => taxa,
                      ),
                  child: const Text('Scegli'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Scegli'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('pick-species-1717')));
        await tester.pumpAndSettle();
        expect(original.toMap(), before);
        if (fail) {
          expect(result, isNull);
          expect(store.observations, isEmpty);
          expect(find.text('Specie non salvata. Riprova.'), findsOneWidget);
        } else {
          expect(result!.taxonItalicId, 1717);
          expect(
            store.observations.single.taxonName,
            taxa.first.scientificName,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'The diary card assigns from the list without opening the key or observation page',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final photo = File(
        'android/app/src/main/res/mipmap-mdpi/ic_launcher.png',
      ).readAsBytesSync();
      final store = _Store()
        ..observations = [
          Observation(
            id: 'first',
            createdAt: DateTime.now(),
            photoBytes: photo,
          ),
        ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DiaryPage(store: store, loadTaxa: () async => taxa),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('diary-choose-species-first')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pick-species-1717')));
      await tester.pumpAndSettle();
      expect(find.text(taxa.first.scientificName), findsOneWidget);
      expect(store.observations.single.photoBytes, photo);
      expect(store.observations.single.rank, IdentificationRank.species);
      expect(tester.takeException(), isNull);
    },
  );
}

class _Store extends AppStore {
  _Store() : super(ObservationRepository(factory: newIdbFactoryMemory())) {
    loading = false;
  }
  bool fail = false;
  @override
  Future<void> save(Observation observation) async {
    if (fail) throw StateError('unavailable');
    observations = [observation];
    notifyListeners();
  }
}
