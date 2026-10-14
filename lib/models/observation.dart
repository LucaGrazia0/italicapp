import 'dart:typed_data';

enum IdentificationRank { undetermined, family, genus, species }

class Observation {
  Observation({
    required this.id,
    required this.createdAt,
    required this.latitude,
    required this.longitude,
    required this.horizontalAccuracy,
    this.gpsAltitude,
    this.altitudeAccuracy,
    this.substrate,
    this.notes = '',
    this.rank = IdentificationRank.undetermined,
    this.taxonName,
    this.photoBytes,
    this.photoName,
  });

  final String id;
  final DateTime createdAt;
  double latitude;
  double longitude;
  double horizontalAccuracy;
  double? gpsAltitude;
  double? altitudeAccuracy;
  String? substrate;
  String notes;
  IdentificationRank rank;
  String? taxonName;
  Uint8List? photoBytes;
  String? photoName;

  Map<String, Object?> toMap() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'latitude': latitude,
    'longitude': longitude,
    'horizontalAccuracy': horizontalAccuracy,
    'gpsAltitude': gpsAltitude,
    'altitudeAccuracy': altitudeAccuracy,
    'substrate': substrate,
    'notes': notes,
    'rank': rank.name,
    'taxonName': taxonName,
    'photoBytes': photoBytes,
    'photoName': photoName,
  };

  factory Observation.fromMap(Map map) {
    final rankName = map['rank'] as String? ?? 'undetermined';
    return Observation(
      id: map['id'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      horizontalAccuracy: (map['horizontalAccuracy'] as num).toDouble(),
      gpsAltitude: (map['gpsAltitude'] as num?)?.toDouble(),
      altitudeAccuracy: (map['altitudeAccuracy'] as num?)?.toDouble(),
      substrate: map['substrate'] as String?,
      notes: map['notes'] as String? ?? '',
      rank: IdentificationRank.values.firstWhere(
        (e) => e.name == rankName,
        orElse: () => IdentificationRank.undetermined,
      ),
      taxonName: map['taxonName'] as String?,
      photoBytes: map['photoBytes'] == null
          ? null
          : Uint8List.fromList(List<int>.from(map['photoBytes'] as List)),
      photoName: map['photoName'] as String?,
    );
  }
}
