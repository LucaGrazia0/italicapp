import 'dart:convert';
import 'package:flutter/services.dart';

class GeoRectangle {
  const GeoRectangle(this.south, this.west, this.north, this.east);
  final double south, west, north, east;
  bool contains(double lat, double lon) =>
      lat.isFinite &&
      lon.isFinite &&
      lat >= south &&
      lat <= north &&
      lon >= west &&
      lon <= east;
}

class ItalianRegion {
  ItalianRegion(this.id, this.name, this.rings) {
    final points = rings.expand((r) => r);
    west = points.map((p) => p[0]).reduce((a, b) => a < b ? a : b);
    east = points.map((p) => p[0]).reduce((a, b) => a > b ? a : b);
    south = points.map((p) => p[1]).reduce((a, b) => a < b ? a : b);
    north = points.map((p) => p[1]).reduce((a, b) => a > b ? a : b);
  }
  final String id, name;
  final List<List<List<double>>> rings;
  late final double west, east, south, north;
  bool contains(double lat, double lon) {
    if (!GeoRectangle(south, west, north, east).contains(lat, lon)) {
      return false;
    }
    // Even/odd rule supports multipart regions, islands and interior holes.
    var inside = false;
    for (final ring in rings) {
      for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
        final a = ring[i], b = ring[j];
        final cross =
            (lon - a[0]) * (b[1] - a[1]) - (lat - a[1]) * (b[0] - a[0]);
        if (cross.abs() < 1e-12 &&
            lon >= (a[0] < b[0] ? a[0] : b[0]) &&
            lon <= (a[0] > b[0] ? a[0] : b[0]) &&
            lat >= (a[1] < b[1] ? a[1] : b[1]) &&
            lat <= (a[1] > b[1] ? a[1] : b[1])) {
          return true;
        }
        if ((a[1] > lat) != (b[1] > lat) &&
            lon < (b[0] - a[0]) * (lat - a[1]) / (b[1] - a[1]) + a[0]) {
          inside = !inside;
        }
      }
    }
    return inside;
  }
}

class ItalianRegions {
  ItalianRegions(this.regions);
  final List<ItalianRegion> regions;
  static Future<ItalianRegions>? _loading;
  static Future<ItalianRegions> load() =>
      _loading ??= _read().catchError((Object e) {
        _loading = null;
        throw e;
      });
  static Future<ItalianRegions> _read() async {
    final data =
        jsonDecode(
              await rootBundle.loadString(
                'assets/geography/italian_regions_2026.json',
              ),
            )
            as Map;
    return ItalianRegions([
      for (final r in data['regions'] as List)
        ItalianRegion(r['id'] as String, r['name'] as String, [
          for (final ring in r['rings'] as List)
            [
              for (final p in ring as List)
                [(p[0] as num).toDouble(), (p[1] as num).toDouble()],
            ],
        ]),
    ]);
  }

  ItalianRegion? at(double? lat, double? lon) {
    if (lat == null || lon == null) return null;
    for (final region in regions) {
      if (region.contains(lat, lon)) return region;
    }
    return null;
  }
}

class DiaryFilter {
  const DiaryFilter({this.from, this.to, this.regionId, this.rectangle});
  final DateTime? from, to;
  final String? regionId;
  final GeoRectangle? rectangle;
  bool get active =>
      from != null || to != null || regionId != null || rectangle != null;
  bool matches(
    DateTime date,
    double? lat,
    double? lon,
    ItalianRegions? regions,
  ) {
    final day = DateTime(date.year, date.month, date.day);
    if (from != null &&
        day.isBefore(DateTime(from!.year, from!.month, from!.day))) {
      return false;
    }
    if (to != null && day.isAfter(DateTime(to!.year, to!.month, to!.day))) {
      return false;
    }
    if (regionId != null) {
      if (regions == null) return false;
      final region = regions.at(lat, lon);
      if (regionId == 'unknown' ? region != null : region?.id != regionId) {
        return false;
      }
    }
    if (rectangle != null &&
        (lat == null || lon == null || !rectangle!.contains(lat, lon))) {
      return false;
    }
    return true;
  }
}
