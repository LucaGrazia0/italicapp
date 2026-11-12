import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:italicapp/models/map_position.dart';
import 'package:italicapp/models/identification_path.dart';
import 'package:italicapp/models/observation.dart';
import 'package:italicapp/pages/diary_page.dart';
import 'package:italicapp/pages/plot_page.dart';
import 'package:italicapp/services/field_location.dart';
import 'package:italicapp/theme/app_theme.dart';
import 'package:italicapp/widgets/candidate_selection.dart';
import 'plots_test.dart' as fixtures;

void main() {
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> scroll(WidgetTester tester, Finder finder, double delta) =>
      tester.scrollUntilVisible(
        finder,
        delta,
        scrollable: find.byType(Scrollable).first,
      );
  Future<void> settleIO(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapIO(WidgetTester tester, Finder finder) async {
    await tester.runAsync(() => tester.tap(finder));
    await settleIO(tester);
  }

  testWidgets(
    'Diary has a compact achievement button and a plot form with validation and saved optional fields',
    (tester) async {
      phone(tester);
      final store = (await tester.runAsync(fixtures.plotStore))!;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: DiaryPage(store: store)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('open-achievements'))).height,
        lessThan(60),
      );
      await tester.tap(find.text('Plot'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('new-plot')));
      await tester.pumpAndSettle();
      final save = find.byKey(const ValueKey('save-plot'));
      await scroll(tester, save, 300);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text('Inserisci un nome per il plot.'), findsOneWidget);
      final name = find.byKey(const ValueKey('plot-name'));
      await scroll(tester, name, -300);
      await tester.enterText(name, 'Bosco sud');
      await tester.enterText(find.byKey(const ValueKey('plot-area')), '2,5');
      await tester.enterText(
        find.byKey(const ValueKey('plot-notes')),
        'Tre alberi campione',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await scroll(tester, save, 300);
      await tapIO(tester, save);
      expect(store.plots.single.name, 'Bosco sud');
      expect(store.plots.single.areaM2, 2.5);
      expect(store.plots.single.notes, 'Tre alberi campione');
      expect(find.text('Lista specie · 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Plot GPS altitude is MSL; switching to a manual map point clears the measurement',
    (tester) async {
      phone(tester);
      final store = (await tester.runAsync(fixtures.plotStore))!;
      await tester.runAsync(() => store.savePlot(fixtures.example()));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (c) => TextButton(
                onPressed: () => Navigator.push(
                  c,
                  MaterialPageRoute(
                    builder: (_) => PlotFormPage(
                      store: store,
                      plot: store.plots.single,
                      locationCapture: () async => FieldFix(
                        latitude: 46,
                        longitude: 12,
                        accuracy: 4,
                        timestamp: DateTime.now(),
                        seaLevelAltitude: 444,
                        ellipsoidAltitude: 490,
                        altitudeAccuracy: 6,
                      ),
                      mapBuilder: (_, _) => Scaffold(
                        body: Builder(
                          builder: (m) => TextButton(
                            onPressed: () => Navigator.pop(
                              m,
                              const MapPosition(
                                44,
                                10,
                                uncertaintyInMeters: 50,
                              ),
                            ),
                            child: const Text('Punto manuale'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('Modifica'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Modifica'));
      await tester.pumpAndSettle();
      await scroll(tester, find.byKey(const ValueKey('plot-gps')), 300);
      await tester.tap(find.byKey(const ValueKey('plot-gps')));
      await tester.pumpAndSettle();
      expect(find.text('Quota 444.0 m s.l.m.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('plot-map')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Punto manuale'));
      await tester.pumpAndSettle();
      await scroll(tester, find.byKey(const ValueKey('save-plot')), 200);
      await tapIO(tester, find.byKey(const ValueKey('save-plot')));
      expect(store.plots.single.latitude, 44);
      expect(store.plots.single.longitude, 10);
      expect(store.plots.single.seaLevelAltitude, isNull);
      expect(store.plots.single.horizontalAccuracy, isNull);
      expect(store.plots.single.positionSource, 'manual_map');
      expect(store.plots.single.coordinateUncertaintyInMeters, 50);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Manual checklist entries and multi-photo gallery stay linked; choosing a candidate updates the plot',
    (tester) async {
      phone(tester);
      final store = (await tester.runAsync(fixtures.plotStore))!;
      await tester.runAsync(() => store.savePlot(fixtures.example()));
      final picker = fixtures.PlotPicker()
        ..files = [fixtures.photo(1), fixtures.photo(2)];
      Observation? opened;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PlotPage(
            store: store,
            plotId: 'p',
            picker: picker,
            loadTaxa: () async => fixtures.plotTaxa,
            onOpenPhoto: (o) => opened = o,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plot-add-species')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('plot-species-search')),
        'aipolia',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('select-plot-species-1717')));
      await tester.pumpAndSettle();
      await tapIO(tester, find.byKey(const ValueKey('confirm-plot-species')));
      expect(store.plots.single.species.single.name, 'Physcia aipolia');
      expect(find.text('Lista specie · 1'), findsOneWidget);
      await tester.tap(find.text('Foto (0)'));
      await tester.pumpAndSettle();
      await tapIO(tester, find.byKey(const ValueKey('plot-add-photos')));
      expect(store.photosForPlot('p').length, 2);
      final tile = find.byKey(
        ValueKey('plot-photo-${store.photosForPlot('p').first.id}'),
      );
      await scroll(tester, tile, 250);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(opened?.plotId, 'p');
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: CandidateSelectionButton(
              taxon: fixtures.plotTaxa[1],
              observation: opened!,
              store: store,
              path: () => IdentificationPath(
                keyId: 'test',
                answers: {},
                savedAt: DateTime.now(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tapIO(tester, find.text('Scegli questo candidato'));
      expect(store.speciesForPlot(store.plots.single).length, 2);
      expect(
        store
            .photosForPlot('p')
            .singleWhere((o) => o.id == opened!.id)
            .taxonItalicId,
        222,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
