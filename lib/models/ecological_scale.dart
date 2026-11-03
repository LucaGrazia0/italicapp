/// Ordinal ITALIC classes; these are not physical measurements.
class EcologicalScaleDefinition {
  const EcologicalScaleDefinition(this.key, this.label, this.min, this.max);

  final String key;
  final String label;
  final int min;
  final int max;

  static const all = [
    EcologicalScaleDefinition('pH of the substrata', 'pH del substrato', 1, 5),
    EcologicalScaleDefinition(
      'Solar irradiation',
      'Irraggiamento solare',
      1,
      5,
    ),
    EcologicalScaleDefinition('Aridity', 'Aridità', 1, 5),
    EcologicalScaleDefinition('Eutrophication', 'Eutrofizzazione', 1, 5),
    EcologicalScaleDefinition(
      'Altitudinal distribution',
      'Distribuzione altitudinale',
      1,
      6,
    ),
    EcologicalScaleDefinition('Poleotolerance', 'Poleotolleranza', 0, 3),
  ];

  /// Reject invalid data rather than treating it as an ecological match.
  (int, int)? range(dynamic value) {
    if (value is! Map) return null;
    final low = value['min'];
    final high = value['max'];
    if (low is! num ||
        high is! num ||
        !low.isFinite ||
        !high.isFinite ||
        low != low.roundToDouble() ||
        high != high.roundToDouble() ||
        low < min ||
        high > max ||
        low > high) {
      return null;
    }
    return (low.toInt(), high.toInt());
  }
}
