import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../models/observation.dart';

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

  Observation applyTo(Observation observation) => Observation.fromMap({
    ...observation.toMap(),
    'latitude': latitude,
    'longitude': longitude,
    'horizontalAccuracy': accuracy,
    'gpsAltitude': ellipsoidAltitude,
    'altitudeAccuracy': null,
    'seaLevelAltitude': seaLevelAltitude,
    'seaLevelAccuracy': altitudeAccuracy,
    'altitudeReference': altitudeSource,
    'positionMeasuredAt': timestamp.toIso8601String(),
    'positionProvider': provider,
    'satellitesUsed': satellitesUsed,
    'positionMocked': mocked,
  });
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
  static StreamSubscription<Position>? _appleStream;
  static Completer<FieldFix>? _applePending;
  static Timer? _appleTimeout;

  static FieldFix fromApplePosition(Position p) => FieldFix.fromMap({
    'latitude': p.latitude, 'longitude': p.longitude, 'accuracy': p.accuracy,
    'timestamp': p.timestamp.millisecondsSinceEpoch,
    // CLLocation.altitude is orthometric (above mean sea level), not WGS84 height.
    'seaLevelAltitude':
        p.hasAltitude &&
            p.altitude.isFinite &&
            p.hasAltitudeAccuracy &&
            p.altitudeAccuracy > 0
        ? p.altitude
        : null,
    'altitudeAccuracy': p.hasAltitudeAccuracy ? p.altitudeAccuracy : null,
    'altitudeSource': 'Apple Core Location · livello del mare',
    'provider': 'core_location', 'mocked': p.isMocked,
  });

  static Future<FieldFix> _captureApple() async {
    if (_applePending != null) {
      throw StateError('Una misura GPS è già in corso.');
    }
    final pending = Completer<FieldFix>();
    _applePending = pending;
    FieldFix? best;
    var altitudeSamples = 0;
    void finish([Object? error]) {
      if (!identical(_applePending, pending)) return;
      _appleTimeout?.cancel();
      _appleTimeout = null;
      unawaited(_appleStream?.cancel());
      _appleStream = null;
      _applePending = null;
      if (error != null) {
        pending.completeError(error);
      } else if (best != null) {
        pending.complete(best);
      } else {
        pending.completeError(
          StateError(
            'Nessuna posizione recente. Spostati all’aperto e riprova.',
          ),
        );
      }
    }

    _appleTimeout = Timer(const Duration(seconds: 35), finish);
    try {
      _appleStream =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.best,
              distanceFilter: 0,
            ),
          ).listen(
            (p) {
              if (!identical(_applePending, pending)) return;
              if (DateTime.now().difference(p.timestamp).inSeconds.abs() > 15) {
                return;
              }
              try {
                final fix = fromApplePosition(p);
                if (fix.seaLevelAltitude != null) altitudeSamples++;
                final current = best;
                if (current == null ||
                    (fix.seaLevelAltitude != null &&
                        current.seaLevelAltitude == null &&
                        fix.accuracy <=
                            (current.accuracy * 2).clamp(
                              30,
                              double.infinity,
                            )) ||
                    (fix.seaLevelAltitude != null &&
                        current.seaLevelAltitude != null &&
                        (fix.accuracy < current.accuracy ||
                            (fix.accuracy <=
                                    (current.accuracy * 1.5).clamp(
                                      15,
                                      double.infinity,
                                    ) &&
                                (fix.altitudeAccuracy ?? double.infinity) <
                                    (current.altitudeAccuracy ??
                                        double.infinity)))) ||
                    (fix.seaLevelAltitude == null &&
                        current.seaLevelAltitude != null &&
                        current.accuracy >
                            (fix.accuracy * 2).clamp(30, double.infinity)) ||
                    (fix.seaLevelAltitude == null &&
                        current.seaLevelAltitude == null &&
                        fix.accuracy < current.accuracy)) {
                  best = fix;
                }
                if (best?.seaLevelAltitude != null &&
                    best!.accuracy <= 10 &&
                    altitudeSamples >= 2) {
                  finish();
                }
              } on FormatException {
                /* Ignore an invalid fix while the receiver settles. */
              }
            },
            onError: (Object error) => finish(error),
            onDone: finish,
          );
    } catch (error) {
      finish(error);
    }
    return pending.future;
  }

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
        'Consenti la posizione precisa nelle impostazioni di Italic Go.',
      );
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final data = await channel.invokeMapMethod<String, dynamic>('capture');
      if (data == null) throw StateError('Nessuna misura GPS disponibile.');
      return FieldFix.fromMap(data);
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      return _captureApple();
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
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      final pending = _applePending;
      _applePending = null;
      _appleTimeout?.cancel();
      _appleTimeout = null;
      await _appleStream?.cancel();
      _appleStream = null;
      if (pending != null && !pending.isCompleted) {
        pending.completeError(
          PlatformException(code: 'CANCELLED', message: 'Misura annullata.'),
        );
      }
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await channel.invokeMethod<void>('cancel');
      } catch (_) {
        /* Page may have closed with the engine. */
      }
    }
  }
}
