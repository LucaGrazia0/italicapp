import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class OfficialSpeciesKey {
  const OfficialSpeciesKey(this.url, this.names);
  final Uri url;
  final List<String> names;
}

class ItalicKeymakerClient {
  ItalicKeymakerClient({http.Client? client})
    : _client = client ?? http.Client();
  final http.Client _client;
  final _cache = <String, OfficialSpeciesKey>{};
  void close() => _client.close();

  Future<OfficialSpeciesKey> generate(Iterable<String> names) async {
    final taxa =
        names.map((s) => s.trim()).where((s) => s.isNotEmpty).toSet().toList()
          ..sort();
    if (taxa.length < 2 || taxa.length > 100) {
      throw const FormatException('Seleziona un gruppo di 2–100 taxa.');
    }
    final signature = jsonEncode(taxa);
    if (_cache[signature] case final key?) return key;
    final response = await _client
        .post(
          Uri.parse('https://italic.units.it/api/v2/keymaker'),
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: utf8.encode(signature),
        )
        .timeout(const Duration(seconds: 45));
    if (response.statusCode == 429) {
      throw StateError('ITALIC è occupato. Attendi qualche istante e riprova.');
    }
    if (response.statusCode != 200) {
      throw StateError('ITALIC non ha restituito una chiave. Riprova.');
    }
    final raw = jsonDecode(utf8.decode(response.bodyBytes));
    if (raw is! Map || raw['key_id'] is! String || raw['link'] is! String) {
      throw const FormatException('Risposta della chiave non valida.');
    }
    final id = raw['key_id'] as String;
    final uri = Uri.tryParse(raw['link'] as String);
    if (!RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(id) ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'italic.units.it' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.path != '/key-maker/$id/nodes/1/interactive' ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('Collegamento ITALIC non valido.');
    }
    // `records` are opaque internal IDs, not a species coverage count.
    final key = OfficialSpeciesKey(uri, List.unmodifiable(taxa));
    _cache[signature] = key;
    return key;
  }
}
