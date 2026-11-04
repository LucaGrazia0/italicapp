class PlotSpecies {
  const PlotSpecies({
    required this.name,
    this.italicId,
    this.abundance = '',
    this.notes = '',
  });
  final String name, abundance, notes;
  final int? italicId;
  Map<String, Object?> toMap() => {
    'name': name,
    'italicId': italicId,
    'abundance': abundance,
    'notes': notes,
  };
  factory PlotSpecies.fromMap(Map m) => PlotSpecies(
    name: m['name'] as String,
    italicId: (m['italicId'] as num?)?.toInt(),
    abundance: m['abundance'] as String? ?? '',
    notes: m['notes'] as String? ?? '',
  );
  String get key => name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

class FieldPlot {
  FieldPlot({
    required this.id,
    required this.name,
    required this.sampledAt,
    required this.createdAt,
    this.notes = '',
    this.areaM2,
    this.latitude,
    this.longitude,
    this.seaLevelAltitude,
    this.horizontalAccuracy,
    this.seaLevelAccuracy,
    this.positionSource,
    this.positionMeasuredAt,
    this.altitudeReference,
    List<PlotSpecies> species = const [],
  }) : species = List.unmodifiable(species);
  final String id, name, notes;
  final DateTime sampledAt, createdAt;
  final double? areaM2,
      latitude,
      longitude,
      seaLevelAltitude,
      horizontalAccuracy,
      seaLevelAccuracy;
  final String? positionSource, altitudeReference;
  final DateTime? positionMeasuredAt;
  final List<PlotSpecies> species;
  bool get hasPosition =>
      latitude != null &&
      longitude != null &&
      latitude!.isFinite &&
      longitude!.isFinite &&
      latitude!.abs() <= 90 &&
      longitude!.abs() <= 180;
  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'sampledAt': sampledAt.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'notes': notes,
    'areaM2': areaM2,
    'latitude': latitude,
    'longitude': longitude,
    'seaLevelAltitude': seaLevelAltitude,
    'horizontalAccuracy': horizontalAccuracy,
    'seaLevelAccuracy': seaLevelAccuracy,
    'positionSource': positionSource,
    'positionMeasuredAt': positionMeasuredAt?.toIso8601String(),
    'altitudeReference': altitudeReference,
    'species': species.map((s) => s.toMap()).toList(),
  };
  factory FieldPlot.fromMap(Map m) {
    double? number(String key) {
      final v = m[key];
      return v is num && v.isFinite ? v.toDouble() : null;
    }

    return FieldPlot(
      id: m['id'] as String,
      name: m['name'] as String,
      sampledAt: DateTime.parse(m['sampledAt'] as String),
      createdAt: DateTime.parse(m['createdAt'] as String),
      notes: m['notes'] as String? ?? '',
      areaM2: number('areaM2'),
      latitude: number('latitude'),
      longitude: number('longitude'),
      seaLevelAltitude: number('seaLevelAltitude'),
      horizontalAccuracy: number('horizontalAccuracy'),
      seaLevelAccuracy: number('seaLevelAccuracy'),
      positionSource: m['positionSource'] as String?,
      positionMeasuredAt: DateTime.tryParse(
        m['positionMeasuredAt']?.toString() ?? '',
      ),
      altitudeReference: m['altitudeReference'] as String?,
      species: (m['species'] as List? ?? [])
          .whereType<Map>()
          .map(PlotSpecies.fromMap)
          .toList(),
    );
  }
}
