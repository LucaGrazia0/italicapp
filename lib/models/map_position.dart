/// A point explicitly chosen on a map, with optional user-estimated uncertainty.
class MapPosition {
  const MapPosition(this.latitude, this.longitude, {this.uncertaintyInMeters});

  final double latitude, longitude;
  final double? uncertaintyInMeters;

  static bool validUncertainty(double? value) =>
      value == null || (value.isFinite && value > 0 && value <= 20000000);
}
