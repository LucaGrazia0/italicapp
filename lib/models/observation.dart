import 'dart:typed_data';
import 'identification_path.dart';

enum IdentificationRank { undetermined, family, genus, species }

class Observation {
  Observation({
    required this.id,
    required this.createdAt,
    this.latitude,
    this.longitude,
    this.horizontalAccuracy,
    this.gpsAltitude,
    this.altitudeAccuracy,
    this.seaLevelAltitude,
    this.seaLevelAccuracy,
    this.altitudeReference,
    this.positionMeasuredAt,
    this.positionProvider,
    this.satellitesUsed,
    this.positionMocked,
    this.substrate,
    this.notes = '',
    this.rank = IdentificationRank.undetermined,
    this.taxonName,
    this.photoBytes,
    this.photoName,
    this.identificationPath,
    this.plotId,
    this.plotPhotoKey,
    this.taxonItalicId,
    this.observedAt,
    this.sourcePlotId,
    this.sourcePlotName,
  });

  final String id;
  final DateTime createdAt;
  DateTime? observedAt;
  String? sourcePlotId, sourcePlotName;
  DateTime get eventDate => observedAt ?? createdAt;
  double? latitude;
  double? longitude;
  double? horizontalAccuracy;
  double? gpsAltitude;
  double? altitudeAccuracy;
  double? seaLevelAltitude, seaLevelAccuracy;
  String? altitudeReference, positionProvider;
  DateTime? positionMeasuredAt;
  int? satellitesUsed;
  bool? positionMocked;
  String? substrate;
  String notes;
  IdentificationRank rank;
  String? taxonName;
  Uint8List? photoBytes;
  String? photoName;
  IdentificationPath? identificationPath;
  String? plotId, plotPhotoKey;
  int? taxonItalicId;

  bool get hasPosition =>
      latitude != null &&
      longitude != null &&
      latitude!.isFinite &&
      longitude!.isFinite &&
      latitude!.abs() <= 90 &&
      longitude!.abs() <= 180;

  bool get isMapPosition => positionProvider == 'manual_map';

  String get positionLabel => !hasPosition
      ? 'Posizione da aggiungere'
      : positionProvider == 'plot'
      ? 'Posizione del plot'
      : isMapPosition
      ? 'Punto scelto sulla mappa'
      : horizontalAccuracy != null && horizontalAccuracy! > 0
      ? '±${horizontalAccuracy!.toStringAsFixed(1)} m'
      : 'Accuratezza non disponibile';

  /// A manually selected point must not inherit a previous fix's GNSS metadata.
  Observation withMapPosition(double lat, double lon, {DateTime? selectedAt}) {
    if (!lat.isFinite ||
        !lon.isFinite ||
        lat.abs() > 85.05112878 ||
        lon.abs() > 180) {
      throw ArgumentError('Coordinate non valide per la mappa.');
    }
    return Observation.fromMap({
      ...toMap(),
      'latitude': lat,
      'longitude': lon,
      'horizontalAccuracy': null,
      'gpsAltitude': null,
      'altitudeAccuracy': null,
      'seaLevelAltitude': null,
      'seaLevelAccuracy': null,
      'altitudeReference': null,
      'positionMeasuredAt': (selectedAt ?? DateTime.now()).toIso8601String(),
      'positionProvider': 'manual_map',
      'satellitesUsed': null,
      'positionMocked': null,
    });
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'latitude': latitude,
    'longitude': longitude,
    'horizontalAccuracy': horizontalAccuracy,
    'gpsAltitude': gpsAltitude,
    'altitudeAccuracy': altitudeAccuracy,
    'seaLevelAltitude': seaLevelAltitude,
    'seaLevelAccuracy': seaLevelAccuracy,
    'altitudeReference': altitudeReference,
    'positionMeasuredAt': positionMeasuredAt?.toIso8601String(),
    'positionProvider': positionProvider,
    'satellitesUsed': satellitesUsed,
    'positionMocked': positionMocked,
    'substrate': substrate,
    'notes': notes,
    'rank': rank.name,
    'taxonName': taxonName,
    'photoBytes': photoBytes,
    'photoName': photoName,
    'identificationPath': identificationPath?.toMap(),
    if (observedAt != null) 'observedAt': observedAt!.toIso8601String(),
    if (sourcePlotId != null) 'sourcePlotId': sourcePlotId,
    if (sourcePlotName != null) 'sourcePlotName': sourcePlotName,
    if (plotId != null) 'plotId': plotId,
    if (plotPhotoKey != null) 'plotPhotoKey': plotPhotoKey,
    if (taxonItalicId != null) 'taxonItalicId': taxonItalicId,
  };

  factory Observation.fromMap(Map map) {
    final rankName = map['rank'] as String? ?? 'undetermined';
    return Observation(
      id: map['id'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      horizontalAccuracy: (map['horizontalAccuracy'] as num?)?.toDouble(),
      gpsAltitude: (map['gpsAltitude'] as num?)?.toDouble(),
      altitudeAccuracy: (map['altitudeAccuracy'] as num?)?.toDouble(),
      seaLevelAltitude: (map['seaLevelAltitude'] as num?)?.toDouble(),
      seaLevelAccuracy: (map['seaLevelAccuracy'] as num?)?.toDouble(),
      altitudeReference: map['altitudeReference'] as String?,
      positionMeasuredAt: DateTime.tryParse(
        map['positionMeasuredAt']?.toString() ?? '',
      ),
      positionProvider: map['positionProvider'] as String?,
      satellitesUsed: (map['satellitesUsed'] as num?)?.toInt(),
      positionMocked: map['positionMocked'] as bool?,
      substrate: map['substrate'] as String?,
      notes: map['notes'] as String? ?? '',
      rank: IdentificationRank.values.firstWhere(
        (e) => e.name == rankName,
        orElse: () => IdentificationRank.undetermined,
      ),
      taxonName: map['taxonName'] as String?,
      photoBytes: map['photoBytes'] == null
          ? null
          : Uint8List.fromList((map['photoBytes'] as List).cast<int>()),
      photoName: map['photoName'] as String?,
      identificationPath: IdentificationPath.fromMap(map['identificationPath']),
      observedAt: DateTime.tryParse(map['observedAt']?.toString() ?? ''),
      sourcePlotId: map['sourcePlotId'] as String?,
      sourcePlotName: map['sourcePlotName'] as String?,
      plotId: map['plotId'] as String?,
      plotPhotoKey: map['plotPhotoKey'] as String?,
      taxonItalicId: (map['taxonItalicId'] as num?)?.toInt(),
    );
  }
}
