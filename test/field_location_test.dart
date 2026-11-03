import 'package:flutter_test/flutter_test.dart';
import 'package:italicapp/services/field_location.dart';
import 'package:italicapp/models/observation.dart';

void main() {
  Map<String, dynamic> fix() => {
    'latitude': 45.1,
    'longitude': 11.2,
    'accuracy': 4.0,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
    'seaLevelAltitude': 350.0,
    'ellipsoidAltitude': 394.0,
    'altitudeAccuracy': 7.0,
    'altitudeSource': 'AndroidX geoid',
    'provider': 'gps',
    'satellitesUsed': 9,
    'mocked': false,
  };
  test(
    'Sea-level altitude stays distinct from the satellite ellipsoid reading',
    () {
      final f = FieldFix.fromMap(fix());
      expect(f.seaLevelAltitude, 350);
      expect(f.ellipsoidAltitude, 394);
      expect(f.altitudeAccuracy, 7);
      expect(f.satellitesUsed, 9);
      expect(f.precise, true);
    },
  );
  test(
    'Stale and invalid positions are rejected; unavailable altitude is never a fake zero',
    () {
      expect(
        () => FieldFix.fromMap({
          ...fix(),
          'timestamp': DateTime.now()
              .subtract(const Duration(minutes: 3))
              .millisecondsSinceEpoch,
        }),
        throwsFormatException,
      );
      expect(
        () => FieldFix.fromMap({...fix(), 'latitude': 91}),
        throwsFormatException,
      );
      expect(
        () => FieldFix.fromMap({...fix(), 'accuracy': 0}),
        throwsFormatException,
      );
      final f = FieldFix.fromMap({
        ...fix(),
        'seaLevelAltitude': null,
        'altitudeAccuracy': 0,
      });
      expect(f.seaLevelAltitude, isNull);
      expect(f.altitudeAccuracy, isNull);
      final coast = FieldFix.fromMap({...fix(), 'seaLevelAltitude': 0});
      expect(coast.seaLevelAltitude, 0);
    },
  );
  test(
    'New altitude metadata survives storage; legacy readings are not relabelled as sea level',
    () {
      final o = Observation(
        id: 'o',
        createdAt: DateTime.now(),
        latitude: 45,
        longitude: 11,
        horizontalAccuracy: 4,
        gpsAltitude: 394,
        seaLevelAltitude: 350,
        seaLevelAccuracy: 7,
        altitudeReference: 'AndroidX geoid',
        positionMeasuredAt: DateTime.utc(2026, 11, 3),
        positionProvider: 'gps',
        satellitesUsed: 9,
        positionMocked: false,
      );
      final copy = Observation.fromMap(o.toMap());
      expect(copy.seaLevelAltitude, 350);
      expect(copy.gpsAltitude, 394);
      expect(copy.satellitesUsed, 9);
      final legacy = Map.of(o.toMap())
        ..remove('seaLevelAltitude')
        ..remove('altitudeReference');
      expect(Observation.fromMap(legacy).seaLevelAltitude, isNull);
    },
  );
}
