import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:italicapp/models/observation.dart';
import 'package:italicapp/models/identification_path.dart';
import 'package:italicapp/services/observation_export.dart';

Observation exampleObservation() => Observation(
  id: 'sample-1',
  createdAt: DateTime.utc(2026, 11, 2, 12, 30),
  latitude: 45.1234567,
  longitude: -11.7654321,
  horizontalAccuracy: 3.2,
  gpsAltitude: 456.7,
  altitudeAccuracy: 5.4,
  taxonName: 'Physcia adscendens H. Olivier',
  rank: IdentificationRank.species,
  substrate: 'Corteccia',
  notes: 'Lobi, "chiari"\nSeconda riga',
  photoName: 'foto.jpg',
  photoBytes: Uint8List.fromList([1, 2, 3]),
  identificationPath: IdentificationPath(
    keyId: 'physcia',
    answers: {'cilia': KeyAnswer.a},
    selections: {'sorali': 'hood-shaped'},
    savedAt: DateTime.utc(2026, 11, 2),
  ),
);

void main() {
  test(
    'Sea-level elevation is exported only with GPS consent in every format',
    () {
      final o = exampleObservation()
        ..seaLevelAltitude = 412.34
        ..seaLevelAccuracy = 8.76
        ..altitudeReference = 'AndroidX geoid';
      for (final format in ObservationExportFormat.values) {
        final visible = exportObservations([o], format, includeGps: true);
        final hidden = exportObservations([o], format);
        String textOf(ObservationExport data) =>
            data.text + data.files.map((f) => utf8.decode(f.bytes)).join();
        expect(textOf(visible), contains('412.34'), reason: '$format');
        expect(textOf(hidden), isNot(contains('412.34')), reason: '$format');
        expect(textOf(hidden), isNot(contains('8.76')), reason: '$format');
        expect(
          textOf(hidden),
          isNot(contains('AndroidX geoid')),
          reason: '$format',
        );
      }
    },
  );

  test(
    'Summary is usable as text; GPS and photos are excluded unless selected',
    () {
      final o = exampleObservation();
      final result = exportObservations([o], ObservationExportFormat.summary);
      expect(result.files, isEmpty);
      expect(result.text, contains(o.taxonName));
      expect(result.text, contains(o.notes));
      expect(result.text, contains('2 risposte salvate'));
      expect(result.text, isNot(contains('45.1234567')));
      expect(result.text, isNot(contains('456.7')));
      final gps = exportObservations(
        [o],
        ObservationExportFormat.summary,
        includeGps: true,
      );
      expect(gps.text, contains('45.1234567, -11.7654321'));
    },
  );
  test(
    'CSV preserves quotes, newlines, precision and full saved path; blocks formulas',
    () {
      final o = exampleObservation();
      var csv = utf8.decode(
        exportObservations(
          [o],
          ObservationExportFormat.csv,
          includeGps: true,
        ).files.single.bytes,
      );
      expect(csv, startsWith('"id","createdAt"'));
      expect(csv, contains('"Lobi, ""chiari""\nSeconda riga"'));
      expect(csv, contains(',45.1234567,-11.7654321,3.2,456.7,5.4,'));
      expect(csv, contains('""sorali"":""hood-shaped""'));
      o.notes = '=HYPERLINK("https://example.test")';
      csv = utf8.decode(
        exportObservations([o], ObservationExportFormat.csv).files.single.bytes,
      );
      expect(csv, contains('"\'=HYPERLINK('));
      expect(csv, isNot(contains('45.1234567')));
      expect(csv, isNot(contains('latitude')));
    },
  );
  test(
    'GeoJSON roundtrips longitude/latitude and keeps altitude separate; opt-out removes all GPS fields',
    () {
      final o = exampleObservation();
      Map feature(bool gps) =>
          (jsonDecode(
                    utf8.decode(
                      exportObservations(
                        [o],
                        ObservationExportFormat.geojson,
                        includeGps: gps,
                      ).files.single.bytes,
                    ),
                  )['features']
                  as List)
              .single;
      final located = feature(true);
      expect(located['geometry']['coordinates'], [-11.7654321, 45.1234567]);
      expect(located['properties']['gpsAltitude'], 456.7);
      expect(
        located['properties']['identificationPath'],
        o.identificationPath!.toMap(),
      );
      final hidden = feature(false);
      expect(hidden['geometry'], isNull);
      expect(hidden['properties'].containsKey('gpsAltitude'), false);
      expect(jsonEncode(hidden), isNot(contains('45.1234567')));
      expect(jsonEncode(hidden), isNot(contains('456.7')));
    },
  );
  test(
    'Darwin Core CSV exports recorded values without inventing identification or invalid zero uncertainty',
    () {
      final o = exampleObservation()..horizontalAccuracy = 0;
      final csv = utf8.decode(
        exportObservations(
          [o],
          ObservationExportFormat.darwinCore,
          includeGps: true,
        ).files.single.bytes,
      );
      expect(csv, contains('"coordinateUncertaintyInMeters"'));
      expect(csv, contains('"HumanObservation"'));
      expect(csv, contains('"WGS84",,"456.7 m (GPS, riferimento originale)"'));
      expect(csv, contains('"unverified"'));
      o.rank = IdentificationRank.undetermined;
      o.taxonName = null;
      final hidden = utf8.decode(
        exportObservations([
          o,
        ], ObservationExportFormat.darwinCore).files.single.bytes,
      );
      expect(hidden, isNot(contains('WGS84')));
      expect(hidden, isNot(contains('45.1234567')));
      expect(hidden, isNot(contains('456.7')));
      expect(hidden, isNot(contains('Physcia')));
    },
  );
  test(
    'Optional image attachment preserves bytes; exports do not mutate the diary',
    () {
      final o = exampleObservation();
      final before = o.toMap();
      final data = exportObservations(
        [o],
        ObservationExportFormat.csv,
        includePhoto: true,
      );
      expect(data.files.length, 2);
      expect(data.files.last.mimeType, 'image/jpeg');
      expect(data.files.last.name, endsWith('-foto.jpg'));
      expect(data.files.last.bytes, [1, 2, 3]);
      expect(o.toMap(), before);
      expect(
        () => exportObservations([], ObservationExportFormat.csv),
        throwsArgumentError,
      );
      expect(
        () => exportObservations(
          [o, o],
          ObservationExportFormat.csv,
          includePhoto: true,
        ),
        throwsArgumentError,
      );
    },
  );
}
