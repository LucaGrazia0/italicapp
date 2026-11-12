import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:italicapp/models/map_position.dart';
import 'package:italicapp/app_store.dart';
import 'package:italicapp/data/observation_database_native.dart';
import 'package:italicapp/data/observation_repository.dart';
import 'package:italicapp/models/observation.dart';
import 'package:italicapp/pages/map_location_page.dart';
import 'package:italicapp/pages/observation_page.dart';
import 'package:italicapp/services/observation_export.dart';
import 'package:italicapp/services/online_map.dart';
import 'package:italicapp/services/field_location.dart';
import 'observation_export_test.dart' show exampleObservation;

void main() {
  final image = MemoryImage(
    File(
      'android/app/src/main/res/mipmap-mdpi/ic_launcher.png',
    ).readAsBytesSync(),
  );

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  test(
    'Map source check validates the actual service and identifies the app; bad responses fail',
    () async {
      var calls = 0;
      final map = OnlineMap(
        client: MockClient((request) async {
          calls++;
          expect(request.method, 'HEAD');
          expect(request.url, OnlineMap.tileAt(45, 11, 15));
          expect(request.headers['User-Agent'], contains('ItalicGo/'));
          return http.Response(
            '',
            calls == 1 ? 200 : 503,
            headers: {'content-type': 'image/png'},
          );
        }),
      );
      addTearDown(map.close);
      await map.check(45, 11, 15);
      await expectLater(map.check(45, 11, 15), throwsStateError);
    },
  );

  testWidgets(
    'Online map requires an explicit tap, verifies connection again on confirm, and returns the chosen point',
    (tester) async {
      phone(tester);
      MapPosition? result;
      var calls = 0;
      final service = OnlineMap(
        client: MockClient((_) async {
          calls++;
          return http.Response('', 200, headers: {'content-type': 'image/png'});
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await Navigator.push<MapPosition>(
                context,
                MaterialPageRoute(
                  builder: (_) => MapLocationPage(
                    onlineMap: service,
                    tileProvider: _Tiles(image),
                    initialLatitude: 45,
                    initialLongitude: 11,
                  ),
                ),
              ),
              child: const Text('Apri mappa'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Apri mappa'));
      await tester.pumpAndSettle();
      final confirm = find.byKey(const ValueKey('confirm-map-location'));
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      final map = find.byType(FlutterMap);
      final target = tester.getCenter(map) + const Offset(45, 15);
      await tester.tapAt(target);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      final camera = MapCamera.of(tester.element(find.byType(TileLayer)));
      expect(camera.rotation, 0);
      final expectedPoint = camera.center;
      final radiusBeforeZoom = tester
          .widget<Text>(find.byKey(const ValueKey('map-uncertainty-radius')))
          .data;
      await tester.tap(find.byTooltip('Ingrandisci'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('map-uncertainty-radius')))
            .data,
        isNot(radiusBeforeZoom),
      );
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.latitude, isNot(45));
      expect(result!.longitude, isNot(11));
      expect(result!.uncertaintyInMeters, greaterThan(0));
      expect(result!.latitude, closeTo(expectedPoint.latitude, 1e-8));
      expect(result!.longitude, closeTo(expectedPoint.longitude, 1e-8));
      expect(calls, 2);
      expect(find.byType(MapLocationPage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Manual uncertainty is entered before the point, accepts decimal commas and is returned with the marker',
    (tester) async {
      phone(tester);
      MapPosition? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await Navigator.push<MapPosition>(
                context,
                MaterialPageRoute(
                  builder: (_) => MapLocationPage(
                    onlineMap: OnlineMap(
                      client: MockClient(
                        (_) async => http.Response(
                          '',
                          200,
                          headers: {'content-type': 'image/png'},
                        ),
                      ),
                    ),
                    tileProvider: _Tiles(image),
                    initialUncertaintyInMeters: 100,
                  ),
                ),
              ),
              child: const Text('Mappa con incertezza'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Mappa con incertezza'));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('map-position-uncertainty'));
      final confirm = find.byKey(const ValueKey('confirm-map-location'));
      expect(tester.widget<TextField>(field).controller!.text, '100.0');
      expect(
        tester.getTopLeft(field).dy,
        lessThan(tester.getTopLeft(find.byType(FlutterMap)).dy),
      );
      for (final invalid in [
        '0',
        '-10',
        'NaN',
        'Infinity',
        'abc',
        '20000001',
      ]) {
        await tester.enterText(field, invalid);
        await tester.pumpAndSettle();
        expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
        expect(
          tester.widget<TextField>(field).decoration!.errorText,
          isNotNull,
        );
      }
      await tester.enterText(field, '25,5');
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getCenter(find.byType(FlutterMap)));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CircleLayer>(find.byType(CircleLayer))
            .circles
            .single
            .radius,
        25.5,
      );
      await tester.tap(find.byTooltip('Ingrandisci'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CircleLayer>(find.byType(CircleLayer))
            .circles
            .single
            .radius,
        25.5,
      );
      await tester.enterText(field, '-1');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.enterText(field, '25,5');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(result!.uncertaintyInMeters, 25.5);
      expect(find.byType(MapLocationPage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Dragging chooses the crosshair centre and unknown uncertainty stays empty',
    (tester) async {
      phone(tester);
      MapPosition? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await Navigator.push<MapPosition>(
                context,
                MaterialPageRoute(
                  builder: (_) => MapLocationPage(
                    initialLatitude: 45,
                    initialLongitude: 11,
                    onlineMap: OnlineMap(
                      client: MockClient(
                        (_) async => http.Response(
                          '',
                          200,
                          headers: {'content-type': 'image/png'},
                        ),
                      ),
                    ),
                    tileProvider: _Tiles(image),
                  ),
                ),
              ),
              child: const Text('Apri'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Apri'));
      await tester.pumpAndSettle();
      final map = find.byType(FlutterMap);
      final centre = tester.getCenter(map);
      await tester.dragFrom(centre, const Offset(65, -30));
      await tester.pumpAndSettle();
      final camera = MapCamera.of(tester.element(find.byType(TileLayer)));
      expect(camera.center.latitude, isNot(45));
      expect(camera.center.longitude, isNot(11));
      final point = camera.center;
      await tester.tap(find.text('Non nota'));
      await tester.pumpAndSettle();
      expect(find.text('Raggio: Non indicata'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirm-map-location')));
      await tester.pumpAndSettle();
      expect(result!.latitude, closeTo(point.latitude, 1e-8));
      expect(result!.longitude, closeTo(point.longitude, 1e-8));
      expect(result!.uncertaintyInMeters, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Offline map shows retry and cannot confirm; losing connection keeps the selection for retry',
    (tester) async {
      phone(tester);
      var online = false;
      final service = OnlineMap(
        client: MockClient((_) async {
          if (!online) throw const SocketException('offline');
          return http.Response('', 200, headers: {'content-type': 'image/png'});
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MapLocationPage(
            onlineMap: service,
            tileProvider: _Tiles(image),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final confirm = find.byKey(const ValueKey('confirm-map-location'));
      expect(find.byKey(const ValueKey('map-network-error')), findsOneWidget);
      expect(find.byType(FlutterMap), findsNothing);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      online = true;
      await tester.tap(find.text('Riprova'));
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getCenter(find.byType(FlutterMap)));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      online = false;
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('map-network-error')), findsOneWidget);
      expect(find.textContaining('42.500000'), findsOneWidget);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      online = true;
      await tester.tap(find.text('Riprova'));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  for (final fail in [false, true]) {
    testWidgets(
      'Diary map correction ${fail ? "failure preserves" : "success replaces"} GPS metadata and the observation',
      (tester) async {
        phone(tester);
        final original = exampleObservation()..photoBytes = image.bytes;
        final originalMap = original.toMap();
        final store = _Store()..fail = fail;
        await tester.pumpWidget(
          MaterialApp(
            home: ObservationPage(
              observation: original,
              store: store,
              mapBuilder: (_) => Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(
                        context,
                        const MapPosition(46, 12, uncertaintyInMeters: 25.5),
                      ),
                      child: const Text('Conferma punto di prova'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final choose = find.byKey(const ValueKey('choose-map-position'));
        await tester.scrollUntilVisible(
          choose,
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(choose);
        await tester.pump();
        await tester.tap(choose);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Conferma punto di prova'));
        await tester.pumpAndSettle();
        expect(original.toMap(), originalMap);
        if (fail) {
          expect(store.observations, isEmpty);
          expect(
            find.textContaining('Il punto precedente è stato conservato'),
            findsOneWidget,
          );
        } else {
          final saved = store.observations.single;
          expect(saved.latitude, 46);
          expect(saved.longitude, 12);
          expect(saved.isMapPosition, true);
          expect(saved.coordinateUncertaintyInMeters, 25.5);
          expect(saved.horizontalAccuracy, isNull);
          expect(saved.seaLevelAltitude, isNull);
          expect(saved.gpsAltitude, isNull);
          expect(saved.taxonName, original.taxonName);
          expect(
            saved.identificationPath!.toMap(),
            original.identificationPath!.toMap(),
          );
          expect(saved.photoBytes, original.photoBytes);
          await tester.scrollUntilVisible(
            find.text('46.000000, 12.000000'),
            -150,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.text('46.000000, 12.000000'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Cancelling map selection leaves the diary unchanged', (
    tester,
  ) async {
    phone(tester);
    final original = exampleObservation()..photoBytes = image.bytes;
    final before = original.toMap();
    final store = _Store();
    await tester.pumpWidget(
      MaterialApp(
        home: ObservationPage(
          observation: original,
          store: store,
          mapBuilder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Mappa')),
            body: const Text('Mappa da annullare'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final choose = find.byKey(const ValueKey('choose-map-position'));
    await tester.scrollUntilVisible(
      choose,
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(choose);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(original.toMap(), before);
    expect(store.observations, isEmpty);
  });

  for (final fail in [false, true]) {
    testWidgets(
      'Existing diary: GPS ${fail ? "write failure keeps the manual point" : "replaces a manual point and saves fresh altitude"}',
      (tester) async {
        phone(tester);
        final original = exampleObservation().withMapPosition(46, 12)
          ..photoBytes = image.bytes;
        final before = original.toMap();
        final store = _Store()..fail = fail;
        final fix = FieldFix(
          latitude: 45.1,
          longitude: 11.2,
          accuracy: 3,
          timestamp: DateTime.now(),
          seaLevelAltitude: 350,
          ellipsoidAltitude: 400,
          altitudeAccuracy: 5,
          provider: 'gps',
          satellitesUsed: 8,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: ObservationPage(
              observation: original,
              store: store,
              locationCapture: () async => fix,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final gps = find.byKey(const ValueKey('observation-gps'));
        await tester.scrollUntilVisible(
          gps,
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(gps);
        await tester.pump();
        await tester.tap(gps);
        await tester.pumpAndSettle();
        expect(original.toMap(), before);
        if (fail) {
          expect(store.observations, isEmpty);
          expect(
            find.byKey(const ValueKey('observation-location-error')),
            findsOneWidget,
          );
        } else {
          final saved = store.observations.single;
          expect(saved.isMapPosition, false);
          expect(saved.positionProvider, 'gps');
          expect(saved.latitude, 45.1);
          expect(saved.longitude, 11.2);
          expect(saved.seaLevelAltitude, 350);
          expect(saved.seaLevelAccuracy, 5);
          expect(saved.gpsAltitude, 400);
          expect(saved.horizontalAccuracy, 3);
          expect(saved.photoBytes, original.photoBytes);
          expect(saved.notes, original.notes);
          expect(
            saved.identificationPath!.toMap(),
            original.identificationPath!.toMap(),
          );
          final reopened = (await tester.runAsync(
            () => store.repository.all(),
          ))!.single;
          expect(reopened.toMap(), saved.toMap());
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Cancelling GPS in a saved observation ignores a late result and preserves all old metadata',
    (tester) async {
      phone(tester);
      final original = exampleObservation()..photoBytes = image.bytes;
      final before = original.toMap();
      final store = _Store();
      final pending = Completer<FieldFix>();
      await tester.pumpWidget(
        MaterialApp(
          home: ObservationPage(
            observation: original,
            store: store,
            locationCapture: () => pending.future,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final gps = find.byKey(const ValueKey('observation-gps'));
      await tester.scrollUntilVisible(
        gps,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(gps);
      await tester.pump();
      await tester.tap(gps);
      await tester.pump();
      await tester.ensureVisible(find.text('Annulla misura GPS'));
      await tester.tap(find.text('Annulla misura GPS'));
      await tester.pumpAndSettle();
      pending.complete(
        FieldFix(
          latitude: 48,
          longitude: 10,
          accuracy: 3,
          timestamp: DateTime.now(),
        ),
      );
      await tester.pumpAndSettle();
      expect(store.observations, isEmpty);
      expect(original.toMap(), before);
      await tester.scrollUntilVisible(
        gps,
        -150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(gps);
      expect(tester.widget<FilledButton>(gps).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'Missing and manual locations survive native database reopening without invented coordinates, altitude or accuracy',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'italic-map-storage-',
      );
      addTearDown(() => folder.delete(recursive: true));
      final repo = ObservationRepository(
        factory: nativeDatabaseFactoryAt(folder.path),
      );
      final missing = Observation(
        id: 'pending',
        createdAt: DateTime.utc(2026, 11, 3),
        notes: 'Da localizzare',
      );
      await repo.save(missing);
      await repo.close();
      final reopened = ObservationRepository(
        factory: nativeDatabaseFactoryAt(folder.path),
      );
      final pending = (await reopened.all()).single;
      expect(pending.hasPosition, false);
      expect(pending.latitude, isNull);
      final point = pending.withMapPosition(45, 11);
      await reopened.save(point);
      await reopened.close();
      final again = ObservationRepository(
        factory: nativeDatabaseFactoryAt(folder.path),
      );
      final saved = (await again.all()).single;
      expect(saved.toMap(), point.toMap());
      expect(saved.notes, missing.notes);
      expect(saved.isMapPosition, true);
      expect(saved.horizontalAccuracy, isNull);
      expect(saved.seaLevelAltitude, isNull);
      await again.close();
      expect(() => point.withMapPosition(double.nan, 11), throwsArgumentError);
    },
  );

  test(
    'Exports handle missing positions and label manual points, while coordinate opt-out removes provenance',
    () {
      final pending = Observation(
        id: 'pending',
        createdAt: DateTime.utc(2026, 11, 3),
      );
      final manual = exampleObservation().withMapPosition(45, 11);
      final geo = exportObservations(
        [pending, manual],
        ObservationExportFormat.geojson,
        includeGps: true,
      );
      final features = jsonDecode(
        utf8.decode(geo.files.single.bytes),
      )['features'];
      expect(features[0]['geometry'], isNull);
      expect(features[1]['geometry']['coordinates'], [11, 45]);
      expect(features[1]['properties']['positionProvider'], 'manual_map');
      expect(features[1]['properties']['seaLevelAltitude'], isNull);
      expect(features[1]['properties']['horizontalAccuracy'], isNull);
      final summary = observationSummary([pending, manual], includeGps: true);
      expect(summary, contains('Posizione: da aggiungere'));
      expect(summary, contains('punto scelto manualmente'));
      expect(summary, isNot(contains('Accuratezza GPS')));
      for (final format in [
        ObservationExportFormat.csv,
        ObservationExportFormat.geojson,
        ObservationExportFormat.darwinCore,
      ]) {
        final hidden = exportObservations([pending, manual], format);
        expect(
          utf8.decode(hidden.files.single.bytes),
          isNot(contains('manual_map')),
        );
      }
    },
  );
}

class _Tiles extends TileProvider {
  _Tiles(this.image);
  final ImageProvider image;
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      image;
}

class _Store extends AppStore {
  _Store() : super(ObservationRepository(factory: newIdbFactoryMemory()));
  bool fail = false;
  @override
  Future<void> save(Observation o) async {
    if (fail) throw StateError('Disco pieno');
    await super.save(o);
  }
}
