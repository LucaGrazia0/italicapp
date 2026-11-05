import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'online_map.dart';

class PlaceResult {
  const PlaceResult({
    required this.label,
    required this.point,
    this.south,
    this.west,
    this.north,
    this.east,
  });
  final String label;
  final LatLng point;
  final double? south, west, north, east;
  static PlaceResult? fromFeature(Object? value) {
    if (value is! Map ||
        value['geometry'] is! Map ||
        value['properties'] is! Map) {
      return null;
    }
    final coordinates = value['geometry']['coordinates'];
    if (coordinates is! List ||
        coordinates.length < 2 ||
        coordinates[0] is! num ||
        coordinates[1] is! num) {
      return null;
    }
    final lon = (coordinates[0] as num).toDouble(),
        lat = (coordinates[1] as num).toDouble();
    if (!lat.isFinite ||
        !lon.isFinite ||
        lat.abs() > 85.05112878 ||
        lon.abs() > 180) {
      return null;
    }
    final p = value['properties'] as Map;
    final name = p['name']?.toString();
    if (name == null || name.trim().isEmpty) return null;
    final label = [
      name,
      p['city'],
      p['state'],
      p['country'],
    ].whereType<String>().where((s) => s.isNotEmpty).toSet().join(', ');
    double? south, west, north, east;
    final extent = p['extent'];
    if (extent is List &&
        extent.length == 4 &&
        extent.every((n) => n is num && n.isFinite)) {
      west = math.min(
        (extent[0] as num).toDouble(),
        (extent[2] as num).toDouble(),
      );
      east = math.max(
        (extent[0] as num).toDouble(),
        (extent[2] as num).toDouble(),
      );
      south = math.min(
        (extent[1] as num).toDouble(),
        (extent[3] as num).toDouble(),
      );
      north = math.max(
        (extent[1] as num).toDouble(),
        (extent[3] as num).toDouble(),
      );
      if (south.abs() > 85 ||
          north.abs() > 85 ||
          west.abs() > 180 ||
          east.abs() > 180) {
        south = null;
        west = null;
        north = null;
        east = null;
      }
    }
    return PlaceResult(
      label: label,
      point: LatLng(lat, lon),
      south: south,
      west: west,
      north: north,
      east: east,
    );
  }
}

/// Explicit searches only, with an in-memory cache and serialized requests.
/// No device coordinates or diary records are sent to the search service.
class PlaceSearch {
  PlaceSearch({http.Client? client, Uri? endpoint})
    : _client = client ?? http.Client(),
      endpoint =
          endpoint ??
          Uri.parse(
            const String.fromEnvironment(
              'ITALIC_PLACE_SEARCH',
              defaultValue: 'https://photon.komoot.io/api/',
            ),
          );
  final http.Client _client;
  final Uri endpoint;
  static final _cache = <String, List<PlaceResult>>{};
  static Future<void> _queue = Future.value();
  static DateTime? _lastRequest;
  Future<List<PlaceResult>> search(String input) async {
    final query = input.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (query.length < 3) throw ArgumentError('Scrivi almeno tre caratteri.');
    final key = '$endpoint:${query.toLowerCase()}';
    if (_cache.containsKey(key)) return _cache[key]!;
    final previous = _queue;
    late final Future<List<PlaceResult>> job;
    job = () async {
      await previous;
      if (_cache.containsKey(key)) return _cache[key]!;
      if (_lastRequest != null) {
        final delay =
            1100 - DateTime.now().difference(_lastRequest!).inMilliseconds;
        if (delay > 0) {
          await Future<void>.delayed(Duration(milliseconds: delay));
        }
      }
      _lastRequest = DateTime.now();
      final response = await _client
          .get(
            endpoint.replace(
              queryParameters: {
                ...endpoint.queryParameters,
                'q': query,
                'limit': '8',
              },
            ),
            headers: kIsWeb ? null : {'User-Agent': OnlineMap.userAgent},
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 429) {
        throw StateError(
          'Servizio occupato. Attendi qualche secondo e riprova.',
        );
      }
      if (response.statusCode != 200) {
        throw StateError('Ricerca località non disponibile.');
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map || data['features'] is! List) {
        throw const FormatException('Risposta non valida.');
      }
      final results = List<PlaceResult>.unmodifiable(
        (data['features'] as List)
            .map(PlaceResult.fromFeature)
            .whereType<PlaceResult>(),
      );
      if (_cache.length >= 50) _cache.remove(_cache.keys.first);
      _cache[key] = results;
      return results;
    }();
    _queue = job.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return job;
  }

  void close() => _client.close();
}
