import 'dart:convert';
import 'dart:typed_data';
import '../models/observation.dart';

enum ObservationExportFormat { summary, csv, geojson, darwinCore }

extension ObservationExportFormatLabel on ObservationExportFormat {
  String get label => switch (this) {
    ObservationExportFormat.summary => 'Riepilogo da condividere',
    ObservationExportFormat.csv => 'CSV · tabella',
    ObservationExportFormat.geojson => 'GeoJSON · mappa',
    ObservationExportFormat.darwinCore => 'Darwin Core · CSV',
  };
}

class ObservationExportFile {
  const ObservationExportFile(this.name, this.mimeType, this.bytes);
  final String name, mimeType;
  final Uint8List bytes;
}

class ObservationExport {
  const ObservationExport({required this.text, required this.files});
  final String text;
  final List<ObservationExportFile> files;
}

String rankLabel(IdentificationRank rank) => switch (rank) {
  IdentificationRank.undetermined => 'Non determinato',
  IdentificationRank.family => 'Famiglia',
  IdentificationRank.genus => 'Genere',
  IdentificationRank.species => 'Specie',
};

String observationSummary(
  List<Observation> observations, {
  required bool includeGps,
}) {
  final sections = observations.map((o) {
    final date = o.createdAt;
    String two(int n) => n.toString().padLeft(2, '0');
    return [
      o.taxonName?.trim().isNotEmpty == true ? o.taxonName! : 'Non determinato',
      'Data: ${two(date.day)}/${two(date.month)}/${date.year} ${two(date.hour)}:${two(date.minute)}',
      'Livello: ${rankLabel(o.rank)}',
      if (o.substrate != null) 'Substrato: ${o.substrate}',
      if (includeGps) ...[
        'Coordinate: ${o.latitude}, ${o.longitude}',
        'Accuratezza GPS: ±${o.horizontalAccuracy} m',
        if (o.seaLevelAltitude != null) 'Quota s.l.m.: ${o.seaLevelAltitude} m',
        if (o.seaLevelAccuracy != null)
          'Accuratezza quota s.l.m.: ±${o.seaLevelAccuracy} m',
        if (o.gpsAltitude != null) 'Quota GPS originale: ${o.gpsAltitude} m',
        if (o.altitudeAccuracy != null)
          'Accuratezza quota: ±${o.altitudeAccuracy} m',
      ],
      if (o.notes.isNotEmpty) 'Note: ${o.notes}',
      if (o.identificationPath != null)
        'Percorso: ${o.identificationPath!.keyId} · ${o.identificationPath!.answerCount} risposte salvate',
      'ID osservazione: ${o.id}',
    ].join('\n');
  });
  return 'Italicapp · ${observations.length} osservazion${observations.length == 1 ? "e" : "i"}\n\n'
      '${sections.join('\n\n')}\n\nDeterminazioni registrate dall’utente; da verificare sul campione.';
}

ObservationExport exportObservations(
  List<Observation> observations,
  ObservationExportFormat format, {
  bool includeGps = false,
  bool includePhoto = false,
}) {
  if (observations.isEmpty) {
    throw ArgumentError('Seleziona almeno un’osservazione.');
  }
  if (includePhoto && observations.length != 1) {
    throw ArgumentError('La foto si allega a una singola osservazione.');
  }
  final files = <ObservationExportFile>[];
  final summary = observationSummary(observations, includeGps: includeGps);
  final stem = observations.length == 1
      ? 'Italicapp-${observations.single.id.replaceAll(RegExp(r"[^a-zA-Z0-9_-]"), "_")}'
      : 'Italicapp-diario-${observations.length}';
  switch (format) {
    case ObservationExportFormat.summary:
      break;
    case ObservationExportFormat.csv:
      final rows = <List<Object?>>[
        [
          'id',
          'createdAt',
          'taxonName',
          'rank',
          'substrate',
          'notes',
          if (includeGps) ...[
            'latitude',
            'longitude',
            'horizontalAccuracy',
            'gpsAltitude',
            'altitudeAccuracy',
            'seaLevelAltitude',
            'seaLevelAccuracy',
            'altitudeReference',
          ],
          'identificationPath',
        ],
        for (final o in observations)
          [
            o.id,
            o.createdAt.toIso8601String(),
            o.taxonName,
            o.rank.name,
            o.substrate,
            o.notes,
            if (includeGps) ...[
              o.latitude,
              o.longitude,
              o.horizontalAccuracy,
              o.gpsAltitude,
              o.altitudeAccuracy,
              o.seaLevelAltitude,
              o.seaLevelAccuracy,
              o.altitudeReference,
            ],
            o.identificationPath == null
                ? null
                : jsonEncode(o.identificationPath!.toMap()),
          ],
      ];
      files.add(_csvFile('$stem.csv', rows));
    case ObservationExportFormat.geojson:
      final data = {
        'type': 'FeatureCollection',
        'features': [
          for (final o in observations)
            {
              'type': 'Feature',
              'id': o.id,
              'geometry': includeGps
                  ? {
                      'type': 'Point',
                      'coordinates': [o.longitude, o.latitude],
                    }
                  : null,
              'properties': {
                'createdAt': o.createdAt.toIso8601String(),
                'taxonName': o.taxonName,
                'rank': o.rank.name,
                'substrate': o.substrate,
                'notes': o.notes,
                if (includeGps) ...{
                  'horizontalAccuracy': o.horizontalAccuracy,
                  'gpsAltitude': o.gpsAltitude,
                  'altitudeAccuracy': o.altitudeAccuracy,
                  'seaLevelAltitude': o.seaLevelAltitude,
                  'seaLevelAccuracy': o.seaLevelAccuracy,
                  'altitudeReference': o.altitudeReference,
                },
                'identificationPath': o.identificationPath?.toMap(),
              },
            },
        ],
      };
      files.add(
        ObservationExportFile(
          '$stem.geojson',
          'application/geo+json',
          Uint8List.fromList(
            utf8.encode(const JsonEncoder.withIndent('  ').convert(data)),
          ),
        ),
      );
    case ObservationExportFormat.darwinCore:
      final rows = <List<Object?>>[
        [
          'occurrenceID',
          'basisOfRecord',
          'eventDate',
          'scientificName',
          'taxonRank',
          'decimalLatitude',
          'decimalLongitude',
          'geodeticDatum',
          'coordinateUncertaintyInMeters',
          'verbatimElevation',
          'occurrenceRemarks',
          'identificationVerificationStatus',
          'dynamicProperties',
        ],
        for (final o in observations)
          [
            'italicapp:${o.id}',
            'HumanObservation',
            o.createdAt.toIso8601String(),
            o.taxonName,
            o.rank == IdentificationRank.undetermined ? '' : o.rank.name,
            includeGps ? o.latitude : null,
            includeGps ? o.longitude : null,
            includeGps ? 'WGS84' : null,
            includeGps && o.horizontalAccuracy > 0
                ? o.horizontalAccuracy
                : null,
            includeGps && o.seaLevelAltitude != null
                ? '${o.seaLevelAltitude} m s.l.m.'
                : includeGps && o.gpsAltitude != null
                ? '${o.gpsAltitude} m (GPS, riferimento originale)'
                : null,
            o.notes,
            'unverified',
            jsonEncode({
              'substrate': o.substrate,
              if (includeGps) ...{
                'altitudeAccuracy': o.altitudeAccuracy,
                'seaLevelAltitude': o.seaLevelAltitude,
                'seaLevelAccuracy': o.seaLevelAccuracy,
                'altitudeReference': o.altitudeReference,
              },
              'identificationPath': o.identificationPath?.toMap(),
            }),
          ],
      ];
      files.add(_csvFile('$stem-DarwinCore.csv', rows));
  }
  if (includePhoto && observations.single.photoBytes != null) {
    final o = observations.single;
    final extension = o.photoName?.split('.').last.toLowerCase();
    final mime = switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'heic' => 'image/heic',
      'heif' => 'image/heif',
      'webp' => 'image/webp',
      _ => 'application/octet-stream',
    };
    final suffix =
        {'jpg', 'jpeg', 'png', 'heic', 'heif', 'webp'}.contains(extension)
        ? extension
        : 'bin';
    files.add(ObservationExportFile('$stem-foto.$suffix', mime, o.photoBytes!));
  }
  return ObservationExport(
    text: format == ObservationExportFormat.summary
        ? summary
        : 'Italicapp · ${observations.length} osservazioni · ${format.label}. Determinazioni da verificare.',
    files: files,
  );
}

ObservationExportFile _csvFile(
  String name,
  List<List<Object?>> rows,
) => ObservationExportFile(
  name,
  'text/csv',
  Uint8List.fromList(
    utf8.encode(
      '\uFEFF${rows.map((row) => row.map(_cell).join(',')).join('\r\n')}\r\n',
    ),
  ),
);

String _cell(Object? value) {
  if (value == null) return '';
  if (value is num) return value.toString();
  var text = value.toString();
  // Quoting alone does not prevent a spreadsheet from interpreting a formula.
  if (RegExp(r'^[\s]*[=+@-]').hasMatch(text) ||
      text.startsWith('\t') ||
      text.startsWith('\r')) {
    text = "'$text";
  }
  return '"${text.replaceAll('"', '""')}"';
}
