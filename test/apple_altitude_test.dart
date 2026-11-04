import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:italicapp/services/field_location.dart';

class Receiver extends GeolocatorPlatform {
  final samples = StreamController<Position>.broadcast();
  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;
  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      samples.stream;
}

Position sample({
  double horizontal = 4,
  double? altitude = 320,
  double vertical = 6,
  bool valid = true,
  DateTime? timestamp,
}) => Position(
  latitude: 45,
  longitude: 11,
  timestamp: timestamp ?? DateTime.now(),
  accuracy: horizontal,
  altitude: altitude ?? 0,
  altitudeAccuracy: vertical,
  hasAltitude: altitude != null,
  hasAltitudeAccuracy: valid,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GeolocatorPlatform original;
  late Receiver receiver;
  setUp(() {
    original = GeolocatorPlatform.instance;
    receiver = Receiver();
    GeolocatorPlatform.instance = receiver;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });
  tearDown(() async {
    await FieldLocation.cancel();
    await receiver.samples.close();
    GeolocatorPlatform.instance = original;
    debugDefaultTargetPlatformOverride = null;
  });
  Future<void> tick() => Future<void>.delayed(Duration.zero);
  test(
    'Apple MSL altitude includes coast and negative elevations; invalid vertical data is unavailable',
    () {
      expect(
        FieldLocation.fromApplePosition(sample(altitude: 0)).seaLevelAltitude,
        0,
      );
      expect(
        FieldLocation.fromApplePosition(sample(altitude: -12)).seaLevelAltitude,
        -12,
      );
      expect(
        FieldLocation.fromApplePosition(sample()).ellipsoidAltitude,
        isNull,
      );
      expect(
        FieldLocation.fromApplePosition(sample(vertical: 0)).seaLevelAltitude,
        isNull,
      );
      expect(
        FieldLocation.fromApplePosition(sample(valid: false)).seaLevelAltitude,
        isNull,
      );
      expect(
        FieldLocation.fromApplePosition(
          sample(altitude: null),
        ).seaLevelAltitude,
        isNull,
      );
    },
  );
  test(
    'Precise 2D fixes do not end capture before two 3D fixes; old samples are ignored',
    () async {
      var done = false;
      final capture = FieldLocation.capture().then((v) {
        done = true;
        return v;
      });
      await tick();
      receiver.samples.add(sample(altitude: null));
      receiver.samples.add(sample(altitude: null));
      await tick();
      expect(done, false);
      receiver.samples.add(
        sample(timestamp: DateTime.now().subtract(const Duration(minutes: 2))),
      );
      receiver.samples.add(sample(altitude: 321));
      await tick();
      expect(done, false);
      receiver.samples.add(sample(altitude: 322, vertical: 3));
      final fix = await capture;
      expect(fix.seaLevelAltitude, 322);
      expect(fix.altitudeAccuracy, 3);
      expect(fix.provider, 'core_location');
      expect(receiver.samples.hasListener, false);
    },
  );
  test(
    'Better horizontal accuracy replaces a coarse 3D fix even with less vertical accuracy',
    () async {
      final capture = FieldLocation.capture();
      await tick();
      receiver.samples.add(sample(horizontal: 100, vertical: 2));
      receiver.samples.add(sample(horizontal: 5, vertical: 8, altitude: 333));
      final fix = await capture;
      expect(fix.accuracy, 5);
      expect(fix.seaLevelAltitude, 333);
    },
  );
  test(
    'Cancellation closes the stream and a subsequent capture can complete',
    () async {
      final capture = FieldLocation.capture();
      final assertion = expectLater(
        capture,
        throwsA(
          isA<PlatformException>().having((e) => e.code, 'code', 'CANCELLED'),
        ),
      );
      await tick();
      await FieldLocation.cancel();
      await assertion;
      expect(receiver.samples.hasListener, false);
      final retry = FieldLocation.capture();
      await tick();
      receiver.samples.add(sample());
      receiver.samples.add(sample());
      expect((await retry).seaLevelAltitude, 320);
    },
  );
}
