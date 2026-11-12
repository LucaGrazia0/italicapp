import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:italicapp/services/map_uncertainty.dart';

void main() {
  MapCamera camera({
    double latitude = 0,
    double longitude = 0,
    double zoom = 15,
    Size size = const Size(390, 400),
  }) => MapCamera(
    crs: const Epsg3857(),
    center: LatLng(latitude, longitude),
    zoom: zoom,
    rotation: 0,
    nonRotatedSize: size,
  );

  test(
    'One zoom level halves the visible ground radius; latitude is accounted for',
    () {
      final equator = MapUncertainty.radiusInMeters(camera())!;
      final closer = MapUncertainty.radiusInMeters(camera(zoom: 16))!;
      final north = MapUncertainty.radiusInMeters(camera(latitude: 60))!;
      expect(closer / equator, closeTo(.5, .001));
      expect(north / equator, closeTo(.5, .003));
      // 127 pixels at zoom 15 on the equator: approximately 607 m.
      expect(equator, inInclusiveRange(600, 610));
    },
  );

  test(
    'The circle fits narrow and short screens and ignores an unlaid-out map',
    () {
      expect(MapUncertainty.screenRadius(const Size(390, 400)), 127);
      expect(MapUncertainty.screenRadius(const Size(800, 200)), 68);
      expect(MapUncertainty.radiusInMeters(camera(size: Size.zero)), isNull);
      expect(
        MapUncertainty.radiusInMeters(camera(size: const Size(-1, -1))),
        isNull,
      );
    },
  );

  test(
    'Longitude wrapping keeps the uncertainty correct across the date line',
    () {
      final wrapped = MapUncertainty.radiusInMeters(
        camera(longitude: 179.9999),
      )!;
      final normal = MapUncertainty.radiusInMeters(camera())!;
      expect(wrapped, closeTo(normal, .01));
      expect(MapUncertainty.normalize(const LatLng(45, 181)).longitude, -179);
    },
  );
}
