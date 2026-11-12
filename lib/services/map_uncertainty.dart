import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Ground radius represented by the visible selection circle, without GPS.
class MapUncertainty {
  static double screenRadius(Size size) =>
      size.width.isFinite &&
          size.height.isFinite &&
          size.width > 0 &&
          size.height > 0
      ? math.min(127, size.shortestSide * .34)
      : 0;

  static LatLng normalize(LatLng point) => LatLng(
    point.latitude.clamp(-85.05112878, 85.05112878),
    (point.longitude + 180) % 360 - 180,
  );

  static double? radiusInMeters(MapCamera camera) {
    final radius = screenRadius(camera.nonRotatedSize);
    if (radius <= 0) return null;
    // This picker uses a north-up EPSG:3857 map. Calculate its longitude
    // span directly to avoid projection clamping at the international date line.
    final center = normalize(camera.center);
    final longitudeSpan = radius / camera.crs.scale(camera.zoom) * 360;
    final edge = normalize(
      LatLng(center.latitude, center.longitude + longitudeSpan),
    );
    final distance = const Distance(roundResult: false)(center, edge);
    return distance.isFinite && distance > 0 && distance <= 20000000
        ? distance
        : null;
  }

  static String label(double? value) => value == null
      ? 'Non indicata'
      : value >= 1000
      ? '${(value / 1000).toStringAsFixed(value < 10000 ? 2 : 1)} km'
      : '${value.toStringAsFixed(value < 10 ? 1 : 0)} m';
}
