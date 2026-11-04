import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:share_plus/share_plus.dart';
import 'package:italicapp/app_store.dart';
import 'package:italicapp/data/observation_repository.dart';
import 'package:italicapp/data/plot_repository.dart';
import 'package:italicapp/data/italic_reference_repository.dart';
import 'package:italicapp/models/field_plot.dart';
import 'package:italicapp/models/observation.dart';
import 'package:italicapp/services/diary_filter.dart';
import 'package:italicapp/services/field_dataset.dart';
import 'package:italicapp/services/map_categories.dart';
import 'package:italicapp/services/field_achievements.dart';
import 'package:italicapp/pages/inaturalist_share_page.dart';
import 'package:italicapp/pages/diary_page.dart';
import 'package:italicapp/pages/plot_page.dart';

final day = DateTime(2026, 10, 20);
FieldPlot samplePlot() => FieldPlot(
  id: 'p',
  name: 'Plot di prova',
  createdAt: day,
  sampledAt: day,
  latitude: 46.067,
  longitude: 11.121,
  seaLevelAltitude: 198,
  substrate: 'Corteccia',
  areaM2: 25,
  species: const [
    PlotSpecies(name: 'Physcia aipolia', italicId: 1717, abundance: '2a'),
    PlotSpecies(name: 'Peltigera canina', italicId: 20),
  ],
);
Observation samplePhoto(String id, {bool located = false}) => Observation(
  id: id,
  createdAt: day.add(const Duration(days: 10)),
  plotId: 'p',
  taxonName: 'Physcia aipolia',
  taxonItalicId: 1717,
  rank: IdentificationRank.species,
  latitude: located ? 45 : null,
  longitude: located ? 9 : null,
  photoName: 'test.png',
  photoBytes: File(
    'android/app/src/main/res/mipmap-mdpi/ic_launcher.png',
  ).readAsBytesSync(),
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('New medals have exact names, materials and thresholds', () {
    expect(fieldAchievements.map((a) => a.target), [1, 10, 50, 100, 500, 1000]);
    expect(fieldAchievements.map((a) => a.title), [
      'Medaglia Cesi',
      'Medaglia Anzi',
      'Medaglia Massalongo',
      'Medaglia Cengia Sambo',
      'Medaglia Acharius',
      'Medaglia Nimis',
    ]);
    for (final name in achievementMedals) {
      expect(File('assets/medals/$name.png').lengthSync(), greaterThan(100000));
    }
  });
  test(
    'Official regions identify all 20 capitals, islands, foreign points and missing coordinates offline',
    () async {
      final regions = await ItalianRegions.load();
      expect(regions.regions.length, 20);
      final capitals = <String, List<double>>{
        '1': [45.07, 7.69],
        '2': [45.737, 7.32],
        '3': [45.464, 9.19],
        '4': [46.067, 11.121],
        '5': [45.438, 12.327],
        '6': [45.65, 13.77],
        '7': [44.407, 8.934],
        '8': [44.495, 11.343],
        '9': [43.77, 11.255],
        '10': [43.111, 12.389],
        '11': [43.615, 13.518],
        '12': [41.9, 12.49],
        '13': [42.35, 13.4],
        '14': [41.56, 14.66],
        '15': [40.85, 14.27],
        '16': [41.117, 16.87],
        '17': [40.64, 15.8],
        '18': [38.91, 16.59],
        '19': [38.12, 13.36],
        '20': [39.22, 9.12],
      };
      for (final c in capitals.entries) {
        expect(regions.at(c.value[0], c.value[1])?.id, c.key, reason: c.key);
      }
      expect(regions.at(48.85, 2.35), isNull);
      expect(regions.at(null, null), isNull);
    },
  );
  test('Polygon holes and multipart islands follow even odd membership', () {
    final r = ItalianRegion('x', 'test', [
      [
        [0, 0],
        [10, 0],
        [10, 10],
        [0, 10],
        [0, 0],
      ],
      [
        [3, 3],
        [7, 3],
        [7, 7],
        [3, 7],
        [3, 3],
      ],
      [
        [20, 20],
        [21, 20],
        [21, 21],
        [20, 21],
        [20, 20],
      ],
    ]);
    expect(r.contains(1, 1), true);
    expect(r.contains(5, 5), false);
    expect(r.contains(20.5, 20.5), true);
    expect(r.contains(50, 50), false);
  });
  test(
    'Diary, plot, map and export share inclusive date and geographic filters',
    () async {
      final store = AppStore(
        ObservationRepository(factory: newIdbFactoryMemory()),
      );
      await store.init();
      await store.loadRegions();
      await store.savePlot(samplePlot());
      await store.save(samplePhoto('photo'));
      await store.save(
        Observation(
          id: 'outside',
          createdAt: day,
          latitude: 41.9,
          longitude: 12.49,
        ),
      );
      store.setDiaryFilter(
        DiaryFilter(
          from: day,
          to: day,
          regionId: '4',
          rectangle: const GeoRectangle(46, 11, 47, 12),
        ),
      );
      expect(store.filteredPlots.length, 1);
      expect(store.filteredObservations.map((o) => o.id), ['photo']);
      expect(
        store.mapObservations.length,
        2,
      ); // one photo + one remaining manual species
      expect(FieldDataset.fromStore(store).occurrences().length, 3);
      store.setDiaryFilter(const DiaryFilter(regionId: '12'));
      expect(store.filteredPlots, isEmpty);
      expect(store.filteredObservations.single.id, 'outside');
      await store.repository.close();
      await store.plotRepository.close();
    },
  );
  test(
    'Delete plot keep option survives restart and preserves original position, date and inherited plot context',
    () async {
      final factory = newIdbFactoryMemory();
      final store = AppStore(ObservationRepository(factory: factory));
      await store.init();
      await store.savePlot(samplePlot());
      await store.save(samplePhoto('inherited'));
      await store.save(samplePhoto('own', located: true));
      await store.deletePlot(samplePlot(), deletePhotos: false);
      final reopened = AppStore(ObservationRepository(factory: factory));
      await reopened.init();
      expect(reopened.plots, isEmpty);
      expect(reopened.observations.length, 2);
      final inherited = reopened.observations.singleWhere(
        (o) => o.id == 'inherited',
      );
      expect(inherited.plotId, isNull);
      expect(inherited.sourcePlotId, 'p');
      expect(inherited.eventDate, day);
      expect(inherited.latitude, 46.067);
      expect(inherited.positionProvider, 'plot');
      expect(inherited.substrate, 'Corteccia');
      expect(
        reopened.observations.singleWhere((o) => o.id == 'own').latitude,
        45,
      );
      await store.repository.close();
      await store.plotRepository.close();
      await reopened.repository.close();
      await reopened.plotRepository.close();
    },
  );
  test(
    'Interrupted plot deletion resumes stored choice and leaves unrelated records intact',
    () async {
      final factory = newIdbFactoryMemory();
      final repo = ObservationRepository(factory: factory),
          plots = PlotRepository(factory: factory);
      await repo.save(samplePhoto('a'));
      await repo.save(Observation(id: 'keep', createdAt: day));
      await plots.save(samplePlot());
      await plots.beginDeletion(samplePlot(), true);
      await repo.resolveDeletedPlot(
        samplePlot(),
        deletePhotos: true,
      ); // interrupt before plot commit
      final store = AppStore(ObservationRepository(factory: factory));
      await store.init();
      expect(store.plots, isEmpty);
      expect(store.observations.single.id, 'keep');
      expect(await store.plotRepository.pendingDeletion(), isNull);
      await repo.close();
      await plots.close();
      await store.repository.close();
      await store.plotRepository.close();
    },
  );
  test(
    'Excel/CSV export includes true typed workbook, DoLichens fields, no double manual occurrences and GPS opt-in',
    () async {
      final data = FieldDataset(
        observations: [samplePhoto('a'), samplePhoto('b')],
        plots: [samplePlot()],
        regions: await ItalianRegions.load(),
      );
      final rows = data.occurrences();
      expect(rows.length, 4);
      expect(rows.every((r) => r.length == FieldDataset.columns.length), true);
      int col(String name) => FieldDataset.columns.indexOf(name);
      expect(rows[1][col('decimalLatitude')], isNull);
      expect(rows[1][col('minimumElevationInMeters')], isNull);
      expect(rows[1][col('stateProvince')], isNull);
      expect(rows[1][col('organismQuantity')], '2a');
      expect(rows[2][col('organismQuantity')], '');
      final gps = data.occurrences(includeGps: true);
      expect(gps[1][col('decimalLatitude')], 46.067);
      expect(gps[1][col('minimumElevationInMeters')], 198);
      expect(gps[1][col('eventDate')], day.toIso8601String());
      final xlsx = data.export(excel: true, includeGps: true);
      final archive = ZipDecoder().decodeBytes(xlsx.bytes);
      expect(archive.findFile('xl/workbook.xml'), isNotNull);
      final sheet = utf8.decode(
        archive.findFile('xl/worksheets/sheet1.xml')!.content,
      );
      expect(sheet, contains('<v>46.067</v>'));
      expect(sheet, contains('scientificName'));
      expect(sheet, contains('state="frozen"'));
      Directory('reports').createSync(recursive: true);
      File('reports/test-field-export.xlsx').writeAsBytesSync(xlsx.bytes);
      final zip = ZipDecoder().decodeBytes(
        data.export(excel: false, includePhotos: true).bytes,
      );
      expect(zip.findFile('photos/a.png'), isNotNull);
      expect(zip.findFile('photos/b.png'), isNotNull);
      expect(zip.findFile('Plots.csv'), isNotNull);
      expect(
        utf8.decode(zip.findFile('Italic-Go-plot.csv')!.content),
        contains('substratum'),
      );
    },
  );
  test(
    'Map status, growth and observed substrate stay distinct; missing values stay unknown',
    () {
      final index = MapCategories(const [
        ItalicTaxon(
          scientificName: 'Physcia aipolia',
          italicId: 1717,
          growthForm: 'Foliose, narrow lobed',
          substrata: 'rocks',
        ),
      ]);
      final o = samplePhoto('a');
      expect(
        index.category(o, FindingColorMode.identification).label,
        'Identificata',
      );
      expect(index.category(o, FindingColorMode.growth).label, 'Foglioso');
      expect(
        index.category(o, FindingColorMode.substrate).label,
        'Non specificato',
      );
      expect(
        index
            .category(o, FindingColorMode.substrate, plotSubstrate: 'Corteccia')
            .label,
        'Corteccia',
      );
      o.rank = IdentificationRank.genus;
      expect(
        index.category(o, FindingColorMode.identification).color,
        const Color(0xFFD32F2F),
      );
      expect(
        index.category(o, FindingColorMode.growth).label,
        'Non specificato',
      );
    },
  );
  testWidgets(
    'iNaturalist shares a real image alone through system sheet, without publishing or authentication',
    (tester) async {
      ShareParams? sent;
      final o = samplePhoto('a');
      await tester.pumpWidget(
        MaterialApp(
          home: INaturalistSharePage(
            observations: [o],
            sender: (p) async {
              sent = p;
              return const ShareResult('', ShareResultStatus.success);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('inat-photo-a')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('inat-photo-a')));
      await tester.pumpAndSettle();
      expect(sent?.files?.single.mimeType, 'image/png');
      expect(sent?.text, isNull);
      expect(sent?.fileNameOverrides, ['a.png']);
      expect(await sent!.files!.single.readAsBytes(), o.photoBytes);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'iNaturalist adapter retains DoLichens metadata in notes and packages photos separately without inventing taxon IDs',
    () async {
      final data = FieldDataset(
        observations: [samplePhoto('a')],
        plots: [samplePlot()],
        regions: await ItalianRegions.load(),
      );
      final rows = data.inaturalistRows(
        includeGps: true,
        recordedBy: 'Osservatore Test',
        identifiedBy: 'Determinatore Test',
      );
      expect(rows.first, [
        'species_guess',
        'observed_on_string',
        'description',
        'place_guess',
        'latitude',
        'longitude',
        'positional_accuracy',
        'tag_list',
      ]);
      expect(rows[1][0], 'Physcia aipolia');
      expect(rows[1][4], 46.067);
      final description = rows[1][2] as String;
      for (final value in [
        'substratum: Corteccia',
        'organismQuantity: 2a',
        'minimumElevationInMeters: 198',
        'recordedBy: Osservatore Test',
        'identifiedBy: Determinatore Test',
        'Plot id: p',
        'italicId',
      ]) {
        expect(description, contains(value));
      }
      expect(data.inaturalistRows()[1][4], isNull);
      expect(data.inaturalistRows()[1][2], isNot(contains('46.067')));
      final zip = ZipDecoder().decodeBytes(
        data.inaturalistPackage(includeGps: true).bytes,
      );
      for (final file in [
        'DoLichens-DarwinCore.xlsx',
        'DoLichens-DarwinCore.csv',
        'iNaturalist-import.csv',
        'photos/a.png',
        'schede/occurrence-1.txt',
        'LEGGIMI.txt',
      ]) {
        expect(zip.findFile(file), isNotNull, reason: file);
      }
      expect(data.records().first['specimenID'], '');
      expect(data.records().first['Dem elevation (m)'], isNull);
    },
  );

  testWidgets(
    'Diary actions use adjacent accessible icon buttons; GPS and map share one row on narrow phones',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = AppStore(
        ObservationRepository(factory: newIdbFactoryMemory()),
      );
      await tester.runAsync(store.init);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DiaryPage(store: store)),
        ),
      );
      await tester.pumpAndSettle();
      final filter = find.byKey(const ValueKey('diary-filters')),
          export = find.byKey(const ValueKey('export-diary'));
      expect(tester.getTopLeft(filter).dy, tester.getTopLeft(export).dy);
      expect(find.text('Esporta / condividi'), findsNothing);
      expect(find.byTooltip('Esporta / condividi'), findsOneWidget);
      await tester.pumpWidget(MaterialApp(home: PlotFormPage(store: store)));
      await tester.pumpAndSettle();
      final gps = find.byKey(const ValueKey('plot-gps')),
          map = find.byKey(const ValueKey('plot-map'));
      await tester.scrollUntilVisible(
        gps,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.getCenter(gps).dy, tester.getCenter(map).dy);
      expect(tester.getTopLeft(gps).dx, lessThan(tester.getTopLeft(map).dx));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(store.repository.close);
      await tester.runAsync(store.plotRepository.close);
    },
  );
}
