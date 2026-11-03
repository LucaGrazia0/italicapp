import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

class FieldFix {
  const FieldFix({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.timestamp,
    this.seaLevelAltitude,
    this.ellipsoidAltitude,
    this.altitudeAccuracy,
    this.altitudeSource,
    this.provider = 'device',
    this.satellitesUsed,
    this.mocked = false,
  });
  final double latitude, longitude, accuracy;
  final double? seaLevelAltitude, ellipsoidAltitude, altitudeAccuracy;
  final DateTime timestamp;
  final String? altitudeSource;
  final String provider;
  final int? satellitesUsed;
  final bool mocked;
  bool get precise => accuracy <= 10;
  factory FieldFix.fromMap(Map data) {
    double? finite(Object? v) => v is num && v.isFinite ? v.toDouble() : null;
    final latitude = finite(data['latitude']),
        longitude = finite(data['longitude']),
        accuracy = finite(data['accuracy']);
    final timestamp = data['timestamp'] is num
        ? DateTime.fromMillisecondsSinceEpoch(
            (data['timestamp'] as num).toInt(),
          )
        : null;
    if (latitude == null ||
        longitude == null ||
        latitude.abs() > 90 ||
        longitude.abs() > 180 ||
        accuracy == null ||
        accuracy <= 0 ||
        timestamp == null ||
        DateTime.now().difference(timestamp).inSeconds.abs() > 65) {
      throw const FormatException(
        'La posizione non è recente o non ha un’accuratezza valida. Riprova.',
      );
    }
    final msl = finite(data['seaLevelAltitude']);
    final vertical = finite(data['altitudeAccuracy']);
    return FieldFix(
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      timestamp: timestamp,
      seaLevelAltitude: msl,
      ellipsoidAltitude: finite(data['ellipsoidAltitude']),
      altitudeAccuracy: msl != null && vertical != null && vertical > 0
          ? vertical
          : null,
      altitudeSource: msl == null ? null : data['altitudeSource'] as String?,
      provider: data['provider'] as String? ?? 'device',
      satellitesUsed: (data['satellitesUsed'] as num?)?.toInt(),
      mocked: data['mocked'] == true,
    );
  }
}

class FieldLocation {
  static const channel = MethodChannel('it.italic.italicapp/gnss');
  static Future<FieldFix> capture() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Attiva la localizzazione del telefono.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError(
        'Consenti la posizione precisa nelle impostazioni di Italicapp.',
      );
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final data = await channel.invokeMapMethod<String, dynamic>('capture');
      if (data == null) throw StateError('Nessuna misura GPS disponibile.');
      return FieldFix.fromMap(data);
    }
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        timeLimit: Duration(seconds: 35),
      ),
    );
    return FieldFix.fromMap({
      'latitude': p.latitude,
      'longitude': p.longitude,
      'accuracy': p.accuracy,
      'timestamp': p.timestamp.millisecondsSinceEpoch,
      'ellipsoidAltitude': p.hasAltitude ? p.altitude : null,
    });
  }

  static Future<void> cancel() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await channel.invokeMethod<void>('cancel');
      } catch (_) {
        /* Page may have closed with the engine. */
      }
    }
  }
}
