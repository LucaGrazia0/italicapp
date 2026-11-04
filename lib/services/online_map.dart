import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Checks the same tile service used by the map, without requesting location.
class OnlineMap {
  OnlineMap({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const tileTemplate = String.fromEnvironment(
    'ITALIC_MAP_TILES',
    defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  );
  static const userAgent =
      'ItalicGo/0.8.11 (it.italic.italicapp; https://github.com/LucaGrazia0/italicapp)';

  static Uri tileAt(double latitude, double longitude, int zoom) {
    final lat = latitude.clamp(-85.05112878, 85.05112878) * math.pi / 180;
    final count = 1 << zoom;
    final x = ((longitude + 180) / 360 * count).floor().clamp(0, count - 1);
    final y =
        ((1 - math.log(math.tan(lat) + 1 / math.cos(lat)) / math.pi) /
                2 *
                count)
            .floor()
            .clamp(0, count - 1);
    return Uri.parse(
      tileTemplate
          .replaceAll('{z}', '$zoom')
          .replaceAll('{x}', '$x')
          .replaceAll('{y}', '$y'),
    );
  }

  Future<void> check(double latitude, double longitude, int zoom) async {
    final response = await _client
        .head(
          tileAt(latitude, longitude, zoom),
          headers: kIsWeb ? null : {'User-Agent': userAgent},
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200 ||
        !(response.headers['content-type'] ?? '').startsWith('image/')) {
      throw StateError('Mappa non raggiungibile.');
    }
  }

  void close() => _client.close();
}
