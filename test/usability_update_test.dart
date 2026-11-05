import 'package:latlong2/latlong.dart' hide Path;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:italicapp/app_store.dart';
import 'package:italicapp/data/observation_repository.dart';
import 'package:italicapp/data/italic_reference_repository.dart';
import 'package:italicapp/models/field_plot.dart';
import 'package:italicapp/models/observation.dart';
import 'package:italicapp/models/identification_path.dart';
import 'package:italicapp/pages/plot_page.dart';
import 'package:italicapp/pages/observation_page.dart';
import 'package:italicapp/pages/species_name_page.dart';
import 'package:italicapp/pages/findings_map_page.dart';
import 'package:italicapp/pages/reconstructed_key_page.dart';
import 'package:italicapp/services/place_search.dart';
import 'package:italicapp/services/reconstructed_key.dart';
import 'package:italicapp/widgets/map_tools.dart';
import 'findings_navigation_test.dart' show Tiles;

final stamp = DateTime(2026, 11, 5);
const reference = [
  ItalicTaxon(
    scientificName: 'Physcia aipolia (Ehrh.) Fürnr.',
    italicId: 1717,
    synonyms: ['Lichen aipolius'],
  ),
  ItalicTaxon(scientificName: 'Physcia adscendens H. Olivier', italicId: 1718),
];
FieldPlot plot(String id, {List<PlotSpecies> species = const []}) => FieldPlot(
  id: id,
  name: 'Plot $id',
  sampledAt: DateTime(2020),
  createdAt: DateTime(2020),
  areaM2: 25,
  latitude: 45,
  longitude: 11,
  seaLevelAltitude: 300,
  substrate: 'Corteccia',
  notes: 'Habitat originale',
  species: species,
);
Observation photo(String id) => Observation(
  id: id,
  createdAt: stamp,
  plotId: 'a',
  taxonName: reference[1].scientificName,
  taxonItalicId: 1718,
  rank: IdentificationRank.species,
  notes: 'Note foto',
  latitude: 45,
  longitude: 11,
  seaLevelAltitude: 300,
  photoName: 'test.png',
  photoBytes: File(
    'android/app/src/main/res/mipmap-mdpi/ic_launcher.png',
  ).readAsBytesSync(),
);
Future<AppStore> memory() async {
  final s = AppStore(ObservationRepository(factory: newIdbFactoryMemory()));
  await s.init();
  return s;
}

Future<void> close(AppStore s) async {
  await s.repository.close();
  await s.plotRepository.close();
}

void phone(WidgetTester t) {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

class FailingNames extends ObservationRepository {
  FailingNames() : super(factory: newIdbFactoryMemory());
  bool fail = false;
  @override
  Future<void> save(Observation o) async {
    if (fail) throw StateError('Disk unavailable');
    await super.save(o);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Copy plot list merges manual and photo species by taxon ID without overwriting target data',
    () async {
      final s = await memory();
      await s.savePlot(
        plot(
          'a',
          species: const [
            PlotSpecies(
              name: 'Physcia aipolia',
              italicId: 1717,
              abundance: '2a',
              notes: 'Source',
            ),
          ],
        ),
      );
      await s.save(photo('p'));
      await s.savePlot(
        plot(
          'b',
          species: const [
            PlotSpecies(
              name: 'Physcia aipolia (Ehrh.) Fürnr.',
              italicId: 1717,
              abundance: '12%',
              notes: 'Target',
            ),
          ],
        ),
      );
      expect(await s.copyPlotSpecies('a', 'b'), 1);
      final target = s.plotById('b')!;
      expect(target.species.length, 2);
      expect(target.species.first.abundance, '12%');
      expect(target.species.first.notes, 'Target');
      expect(target.species.last.abundance, '');
      expect(s.photosForPlot('b'), isEmpty);
      expect(s.photosForPlot('a').length, 1);
      expect(await s.copyPlotSpecies('a', 'b'), 0);
      final reopened = AppStore(
        ObservationRepository(factory: s.repository.factory),
      );
      await reopened.init();
      expect(reopened.plotById('b')!.species.length, 2);
      await close(s);
      await close(reopened);
    },
  );
  test(
    'Manual names retain uncertainty and distinguish species from a genus',
    () {
      expect(manualNameRank('Physcia adscendens'), IdentificationRank.species);
      for (final text in [
        'Physcia cf. adscendens',
        'Physcia cfr. aipolia',
        'Physcia sp.',
        'Physcia ? aipolia',
      ]) {
        expect(manualNameRank(text), IdentificationRank.undetermined);
      }
      expect(manualNameRank('Physcia'), IdentificationRank.genus);
    },
  );
  testWidgets(
    'Duplicate plot creates a fresh record with combined species, without copying photos, coordinates or abundance by default',
    (t) async {
      phone(t);
      final s = (await t.runAsync(memory))!;
      await t.runAsync(
        () => s.savePlot(
          plot(
            'a',
            species: const [
              PlotSpecies(
                name: 'Physcia aipolia',
                italicId: 1717,
                abundance: '2a',
              ),
            ],
          ),
        ),
      );
      await t.runAsync(() => s.save(photo('p')));
      await t.pumpWidget(
        MaterialApp(
          home: PlotFormPage(store: s, template: s.plots.single),
        ),
      );
      await t.pumpAndSettle();
      expect(
        t
            .widget<TextFormField>(find.byKey(const ValueKey('plot-name')))
            .controller!
            .text,
        'Plot a · copia',
      );
      final save = find.byKey(const ValueKey('save-plot'));
      await t.scrollUntilVisible(
        save,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await t.runAsync(() => t.tap(save));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await t.pumpAndSettle();
      expect(s.plots.length, 2);
      final copy = s.plots.singleWhere((p) => p.id != 'a');
      expect(copy.species.length, 2);
      expect(copy.hasPosition, false);
      expect(copy.seaLevelAltitude, isNull);
      expect(copy.sampledAt.year, greaterThan(2020));
      expect(copy.species.every((p) => p.abundance.isEmpty), true);
      expect(s.photosForPlot(copy.id), isEmpty);
      expect(
        s.plots.singleWhere((p) => p.id == 'a').species.single.abundance,
        '2a',
      );
      await t.pumpWidget(const SizedBox());
      await t.runAsync(() => close(s));
    },
  );
  testWidgets(
    'Type species directly in diary and preserve photo, GPS, plot and historical path after restart',
    (t) async {
      phone(t);
      final s = (await t.runAsync(memory))!;
      final o = photo('manual')
        ..rank = IdentificationRank.undetermined
        ..taxonName = null
        ..taxonItalicId = null
        ..identificationPath = IdentificationPath(
          keyId: 'history',
          answers: const {'x': KeyAnswer.a},
          savedAt: stamp,
        );
      await t.runAsync(() => s.save(o));
      await t.pumpWidget(
        MaterialApp(
          home: SpeciesNamePage(
            store: s,
            observation: o,
            loadTaxa: () async => reference,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('manual-species-name')),
        'Physcia adscendens',
      );
      await t.pumpAndSettle();
      await t.runAsync(
        () => t.tap(find.byKey(const ValueKey('save-manual-species'))),
      );
      await t.pumpAndSettle();
      final reopened = AppStore(
        ObservationRepository(factory: s.repository.factory),
      );
      await t.runAsync(reopened.init);
      final saved = reopened.observations.single;
      expect(saved.taxonName, reference[1].scientificName);
      expect(saved.identificationMethod, 'manual');
      expect(saved.taxonItalicId, 1718);
      expect(saved.rank, IdentificationRank.species);
      expect(saved.plotId, 'a');
      expect(saved.notes, 'Note foto');
      expect(saved.seaLevelAltitude, 300);
      expect(saved.identificationPath!.keyId, 'history');
      expect(saved.photoBytes, o.photoBytes);
      await t.pumpWidget(const SizedBox());
      await t.runAsync(() => close(s));
      await t.runAsync(() => close(reopened));
    },
  );
  testWidgets(
    'Free text can be saved with catalogue unavailable; failed writes leave previous name intact',
    (t) async {
      final repo = FailingNames(), s = AppStore(FailingNames());
      await t.runAsync(s.init);
      final o = photo('free');
      await t.runAsync(() => s.save(o));
      await t.pumpWidget(
        MaterialApp(
          home: SpeciesNamePage(
            store: s,
            observation: o,
            loadTaxa: () async => throw StateError('No catalogue'),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('manual-species-name')),
        'Lichenus novus',
      );
      (s.repository as FailingNames).fail = true;
      await t.runAsync(
        () => t.tap(find.byKey(const ValueKey('save-manual-species'))),
      );
      await t.pumpAndSettle();
      expect(o.taxonName, reference[1].scientificName);
      expect(find.textContaining('Nome non salvato.'), findsOneWidget);
      (s.repository as FailingNames).fail = false;
      await t.runAsync(
        () => t.tap(find.byKey(const ValueKey('save-manual-species'))),
      );
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await t.pumpAndSettle();
      expect(s.observations.single.taxonName, 'Lichenus novus');
      expect(s.observations.single.taxonItalicId, isNull);
      expect(s.observations.single.identificationMethod, 'manual');
      await t.pumpWidget(const SizedBox());
      await t.runAsync(() => close(s));
      await repo.close();
    },
  );
  testWidgets(
    'Identification and manual-name buttons are immediately after the diary photo, above location metadata',
    (t) async {
      phone(t);
      final s = (await t.runAsync(memory))!;
      final o = photo('layout');
      await t.pumpWidget(
        MaterialApp(
          home: ObservationPage(observation: o, store: s),
        ),
      );
      await t.pumpAndSettle();
      final identify = find.byKey(const ValueKey('identify-observation')),
          write = find.byKey(const ValueKey('write-observation-species'));
      expect(t.getRect(identify).bottom, lessThan(450));
      expect(t.getCenter(identify).dy, t.getCenter(write).dy);
      expect(
        t.getTopLeft(identify).dy,
        lessThan(t.getTopLeft(find.text('Coordinate')).dy),
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.runAsync(() => close(s));
    },
  );
  test(
    'Place search submits only an explicit query, identifies the app, caches results and parses bounding boxes',
    () async {
      var calls = 0;
      final service = PlaceSearch(
        endpoint: Uri.parse('https://example.test/search-cached'),
        client: MockClient((request) async {
          calls++;
          expect(request.url.queryParameters, {
            'q': 'Paneveggio',
            'limit': '8',
          });
          expect(request.headers['User-Agent'], contains('ItalicGo/'));
          expect(request.url.queryParameters.keys, isNot(contains('lat')));
          return http.Response(
            jsonEncode({
              'features': [
                {
                  'geometry': {
                    'coordinates': [11.75, 46.3],
                  },
                  'properties': {
                    'name': 'Paneveggio',
                    'state': 'Trentino',
                    'extent': [11.7, 46.4, 11.8, 46.2],
                  },
                },
              ],
            }),
            200,
          );
        }),
      );
      final a = await service.search(' Paneveggio '),
          b = await service.search('paneveggio');
      expect(calls, 1);
      expect(identical(a, b), true);
      expect(a.single.south, 46.2);
      expect(a.single.north, 46.4);
      expect(a.single.point.latitude, 46.3);
      service.close();
    },
  );
  test(
    'Place search rejects invalid results and lets failed requests be retried',
    () async {
      var calls = 0;
      final service = PlaceSearch(
        endpoint: Uri.parse('https://example.test/search-retry'),
        client: MockClient((_) async {
          if (calls++ == 0) return http.Response('busy', 429);
          return http.Response(
            jsonEncode({
              'features': [
                {
                  'geometry': {
                    'coordinates': [999, 999],
                  },
                  'properties': {'name': 'Invalid'},
                },
                {
                  'geometry': {
                    'coordinates': [11, 45],
                  },
                  'properties': {'name': 'Valid'},
                },
              ],
            }),
            200,
          );
        }),
      );
      await expectLater(service.search('retry'), throwsStateError);
      final result = await service.search('retry');
      expect(result.single.label, 'Valid');
      await expectLater(service.search('x'), throwsArgumentError);
      service.close();
    },
  );
  testWidgets(
    'Locality lookup waits for Search and returns a public place without touching the diary',
    (t) async {
      var calls = 0;
      await t.pumpWidget(
        MaterialApp(
          home: PlaceSearchPage(
            lookup: (q) async {
              calls++;
              return const [
                PlaceResult(
                  label: 'Paneveggio, Trentino',
                  point: LatLng(46.3, 11.75),
                ),
              ];
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('place-query')),
        'Paneveggio',
      );
      await t.pumpAndSettle();
      expect(calls, 0);
      await t.tap(find.byKey(const ValueKey('submit-place-search')));
      await t.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('Paneveggio, Trentino'), findsOneWidget);
    },
  );
  testWidgets(
    'Map is north-up, filter precedes marker colors, satellite changes tiles and credit while preserving records',
    (t) async {
      phone(t);
      final s = (await t.runAsync(memory))!;
      await t.runAsync(() => s.save(photo('map')));
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FindingsMapPage(store: s, tileProvider: Tiles()),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        t.getTopLeft(find.byKey(const ValueKey('diary-filters'))).dy,
        lessThan(t.getTopLeft(find.byKey(const ValueKey('map-color-mode'))).dy),
      );
      final map = t.widget<FlutterMap>(find.byType(FlutterMap));
      expect(map.options.interactionOptions.flags & InteractiveFlag.rotate, 0);
      expect(
        map.options.interactionOptions.flags & InteractiveFlag.pinchZoom,
        isNot(0),
      );
      await t.tap(find.text('Satellite'));
      await t.pumpAndSettle();
      expect(
        t.widget<TileLayer>(find.byType(TileLayer)).urlTemplate,
        contains('World_Imagery'),
      );
      expect(find.textContaining('Esri, Vantor'), findsOneWidget);
      expect(s.observations.single.latitude, 45);
      expect(s.observations.single.longitude, 11);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.runAsync(() => close(s));
    },
  );
  testWidgets(
    'Terminal candidate and path save share one footer row; redundant back and dictionary are absent',
    (t) async {
      phone(t);
      final taxa =
          (jsonDecode(
                    File(
                      'assets/italic/italic_checklist.json',
                    ).readAsStringSync(),
                  )['taxa']
                  as List)
              .map(
                (r) => ItalicTaxon.fromMap(Map<String, dynamic>.from(r as Map)),
              )
              .toList();
      final key = ReconstructedKey.fromMap(
        jsonDecode(File(ReconstructedKey.asset).readAsStringSync()) as Map,
        taxa,
      );
      final steps = key.pathsFor(1718).first;
      final path = IdentificationPath(
        keyId: key.identity,
        answers: const {},
        selections: {
          for (final step in steps) step.node.id: step.choice.target,
        },
        savedAt: stamp,
      );
      final s = (await t.runAsync(memory))!;
      final o = photo('terminal')..identificationPath = path;
      await t.pumpWidget(
        MaterialApp(
          home: ReconstructedKeyPage(definition: key, observation: o, store: s),
        ),
      );
      await t.pumpAndSettle();
      final choice = find.byKey(const ValueKey('choose-candidate-1718')),
          save = find.byKey(const ValueKey('reconstructed-save'));
      expect(t.getTopLeft(choice).dy, t.getTopLeft(save).dy);
      expect(t.getRect(choice).overlaps(t.getRect(save)), false);
      expect(find.text('Salva percorso'), findsOneWidget);
      expect(find.byKey(const ValueKey('reconstructed-back')), findsNothing);
      expect(find.text('Apri dizionario dei caratteri'), findsNothing);
      expect(
        find.widgetWithText(FilledButton, 'Apri scheda della specie'),
        findsOneWidget,
      );
      await t.tap(find.byKey(const ValueKey('reconstructed-undo')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('reconstructed-result')), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.runAsync(() => close(s));
    },
  );
}
