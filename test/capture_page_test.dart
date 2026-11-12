import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:italicapp/models/map_position.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:italicapp/app_store.dart';
import 'package:italicapp/data/observation_repository.dart';
import 'package:italicapp/models/observation.dart';
import 'package:italicapp/pages/capture_page.dart';
import 'package:italicapp/services/field_location.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(FieldLocation.channel, (call) async {
          if (call.method == 'cancel') return null;
          return {
            'latitude': 45.1,
            'longitude': 11.2,
            'accuracy': 3.0,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'seaLevelAltitude': 350.0,
            'ellipsoidAltitude': 400.0,
            'altitudeAccuracy': 5.0,
            'altitudeSource': 'AndroidX geoid',
            'provider': 'gps',
            'satellitesUsed': 8,
          };
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(FieldLocation.channel, null),
  );
  final imageBytes = File(
    'android/app/src/main/res/mipmap-mdpi/ic_launcher.png',
  ).readAsBytesSync();
  XFile image() => XFile.fromData(
    imageBytes,
    path: '/memory/galleria.png',
    name: 'galleria.png',
    mimeType: 'image/png',
  );
  final gallery = find.byKey(const ValueKey('capture-gallery'));
  final camera = find.byKey(const ValueKey('capture-camera'));
  Future<void> show(
    WidgetTester tester,
    _Picker picker,
    _Store store, {
    VoidCallback? onSaved,
    Widget Function(double?, double?)? mapBuilder,
    Future<FieldFix> Function()? locationCapture,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CapturePage(
            picker: picker,
            store: store,
            onSaved: onSaved ?? () {},
            mapBuilder: mapBuilder,
            locationCapture: locationCapture,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Gallery and camera use distinct sources; cancellation and failures keep the previous image',
    (tester) async {
      final picker = _Picker()..next = image();
      await show(tester, picker, _Store());
      await tester.tap(gallery);
      await tester.pumpAndSettle();
      expect(picker.sources, [ImageSource.gallery]);
      expect(picker.fullMetadata, false);
      expect(
        (tester.widget<Image>(find.byType(Image)).image as MemoryImage).bytes,
        imageBytes,
      );
      picker.next = null;
      await tester.tap(camera);
      await tester.pumpAndSettle();
      expect(picker.sources, [ImageSource.gallery, ImageSource.camera]);
      expect(find.byType(Image), findsOneWidget);
      picker.fail = true;
      await tester.tap(gallery);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Impossibile caricare la foto'),
        findsOneWidget,
      );
      expect(
        (tester.widget<Image>(find.byType(Image)).image as MemoryImage).bytes,
        imageBytes,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'An image returned by Android after process recreation is recovered into the form',
    (tester) async {
      final picker = _Picker()
        ..lost = LostDataResponse(files: [image()], type: RetrieveType.image);
      await show(tester, picker, _Store());
      expect(picker.recovered, 1);
      expect(picker.sources, isEmpty);
      expect(
        (tester.widget<Image>(find.byType(Image)).image as MemoryImage).bytes,
        imageBytes,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Gallery bytes, filename, notes and GPS are saved together in the diary',
    (tester) async {
      final originalLocation = GeolocatorPlatform.instance;
      GeolocatorPlatform.instance = _Location();
      addTearDown(() => GeolocatorPlatform.instance = originalLocation);
      final store = _Store();
      final picker = _Picker()..next = image();
      var saved = false;
      await show(tester, picker, store, onSaved: () => saved = true);
      await tester.tap(gallery);
      await tester.pumpAndSettle();
      final gps = find.byKey(const ValueKey('capture-gps'));
      await tester.scrollUntilVisible(
        gps,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(gps);
      await tester.pump();
      await tester.tap(gps);
      await tester.pumpAndSettle();
      final notes = find.byType(TextField);
      await tester.scrollUntilVisible(
        notes,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(notes, 'Nota del campione');
      final save = find.text('Salva osservazione');
      await tester.scrollUntilVisible(
        save,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(saved, true);
      expect(store.saved!.photoBytes, imageBytes);
      expect(store.saved!.photoName, 'galleria.png');
      expect(store.saved!.notes, 'Nota del campione');
      expect(store.saved!.latitude, 45.1);
      expect(store.saved!.longitude, 11.2);
      expect(store.saved!.horizontalAccuracy, 3);
      expect(store.saved!.gpsAltitude, 400);
      expect(store.saved!.seaLevelAltitude, 350);
      expect(store.saved!.seaLevelAccuracy, 5);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'A photo can be saved without GPS, leaving the position genuinely missing for later map selection',
    (tester) async {
      final store = _Store();
      await show(tester, _Picker()..next = image(), store);
      await tester.tap(gallery);
      await tester.pumpAndSettle();
      final save = find.text('Salva osservazione');
      await tester.scrollUntilVisible(
        save,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(store.saved!.photoBytes, imageBytes);
      expect(store.saved!.hasPosition, false);
      expect(store.saved!.latitude, isNull);
      expect(store.saved!.longitude, isNull);
      expect(store.saved!.horizontalAccuracy, isNull);
      expect(store.saved!.seaLevelAltitude, isNull);
      expect(store.saved!.positionProvider, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'GPS can be replaced by a map point before saving, with no stale altitude or precision',
    (tester) async {
      final store = _Store();
      await show(
        tester,
        _Picker()..next = image(),
        store,
        locationCapture: () async => FieldFix(
          latitude: 45.1,
          longitude: 11.2,
          accuracy: 3,
          timestamp: DateTime.now(),
          seaLevelAltitude: 350,
          ellipsoidAltitude: 400,
          altitudeAccuracy: 5,
          provider: 'gps',
          satellitesUsed: 8,
        ),
        mapBuilder: (lat, lon) {
          expect(lat, 45.1);
          expect(lon, 11.2);
          return Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.pop(
                    context,
                    const MapPosition(46, 12, uncertaintyInMeters: 25.5),
                  ),
                  child: const Text('Punto di prova'),
                ),
              ),
            ),
          );
        },
      );
      await tester.tap(gallery);
      await tester.pumpAndSettle();
      final gps = find.byKey(const ValueKey('capture-gps'));
      await tester.scrollUntilVisible(
        gps,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(gps);
      await tester.pump();
      await tester.tap(gps);
      await tester.pumpAndSettle();
      final map = find.byKey(const ValueKey('capture-map'));
      await tester.ensureVisible(map);
      await tester.ensureVisible(map);
      await tester.pump();
      await tester.tap(map);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Punto di prova'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Salva osservazione'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Salva osservazione'));
      await tester.pumpAndSettle();
      expect(store.saved!.latitude, 46);
      expect(store.saved!.longitude, 12);
      expect(store.saved!.isMapPosition, true);
      expect(store.saved!.coordinateUncertaintyInMeters, 25.5);
      expect(store.saved!.photoBytes, imageBytes);
      expect(store.saved!.seaLevelAltitude, isNull);
      expect(store.saved!.gpsAltitude, isNull);
      expect(store.saved!.horizontalAccuracy, isNull);
      expect(store.saved!.satellitesUsed, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Cancelling GPS ignores a late fix and keeps the selected map point; GPS can then replace it',
    (tester) async {
      final store = _Store();
      final pending = Completer<FieldFix>();
      var calls = 0;
      final fix = FieldFix(
        latitude: 45.1,
        longitude: 11.2,
        accuracy: 4,
        timestamp: DateTime.now(),
        seaLevelAltitude: 350,
        altitudeAccuracy: 5,
        provider: 'gps',
      );
      await show(
        tester,
        _Picker()..next = image(),
        store,
        locationCapture: () =>
            ++calls == 1 ? pending.future : Future.value(fix),
        mapBuilder: (_, _) => Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  const MapPosition(46, 12, uncertaintyInMeters: 25.5),
                ),
                child: const Text('Punto di prova'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(gallery);
      await tester.pumpAndSettle();
      final map = find.byKey(const ValueKey('capture-map'));
      await tester.scrollUntilVisible(
        map,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(map);
      await tester.pump();
      await tester.tap(map);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Punto di prova'));
      await tester.pumpAndSettle();
      final gps = find.byKey(const ValueKey('capture-gps'));
      await tester.ensureVisible(gps);
      await tester.ensureVisible(gps);
      await tester.pump();
      await tester.tap(gps);
      await tester.pump();
      await tester.ensureVisible(find.text('Annulla misura GPS'));
      await tester.tap(find.text('Annulla misura GPS'));
      await tester.pumpAndSettle();
      pending.complete(fix);
      await tester.pumpAndSettle();
      expect(find.textContaining('46.000000, 12.000000'), findsOneWidget);
      await tester.ensureVisible(gps);
      await tester.ensureVisible(gps);
      await tester.pump();
      await tester.tap(gps);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Salva osservazione'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Salva osservazione'));
      await tester.pumpAndSettle();
      expect(store.saved!.isMapPosition, false);
      expect(store.saved!.positionProvider, 'gps');
      expect(store.saved!.latitude, 45.1);
      expect(store.saved!.seaLevelAltitude, 350);
      expect(store.saved!.horizontalAccuracy, 4);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Closing the form while the gallery is open does not update a disposed page',
    (tester) async {
      final picker = _Picker()..pending = Completer<XFile?>();
      await show(tester, picker, _Store());
      await tester.tap(gallery);
      await tester.pump();
      await tester.pumpWidget(const MaterialApp(home: Text('Altra pagina')));
      picker.pending!.complete(image());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}

class _Picker extends ImagePicker {
  XFile? next;
  bool fail = false;
  bool? fullMetadata;
  int recovered = 0;
  LostDataResponse? lost;
  Completer<XFile?>? pending;
  final sources = <ImageSource>[];
  @override
  Future<LostDataResponse> retrieveLostData() async {
    recovered++;
    return lost ?? LostDataResponse.empty();
  }

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    sources.add(source);
    fullMetadata = requestFullMetadata;
    if (fail) throw PlatformException(code: 'photo_access_denied');
    return pending == null ? next : pending!.future;
  }
}

class _Store extends AppStore {
  _Store() : super(ObservationRepository(factory: newIdbFactoryMemory()));
  Observation? saved;
  @override
  Future<void> save(Observation o) async {
    saved = Observation.fromMap(o.toMap());
  }
}

class _Location extends GeolocatorPlatform {
  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;
  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async => Position(
    latitude: 45.1,
    longitude: 11.2,
    timestamp: DateTime.utc(2026, 11, 2),
    accuracy: 3,
    altitude: 400,
    altitudeAccuracy: 5,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}
