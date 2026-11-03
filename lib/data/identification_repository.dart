import 'dart:convert';
import 'scientific_data.dart';
import 'italic_reference_repository.dart';
import '../services/identification_engine.dart';

class GenusKey {
  const GenusKey({required this.genus, required this.name, required this.url});
  final String genus, name;
  final Uri url;

  static GenusKey? fromMap(Map data) {
    final url = Uri.tryParse(data['url']?.toString() ?? '');
    if (url == null ||
        url.scheme != 'https' ||
        url.host != 'italic.units.it' ||
        url.path != '/flora/index.php' ||
        url.queryParameters['procedure'] != 'ext_key_home' ||
        int.tryParse(url.queryParameters['key_id'] ?? '') == null) {
      return null;
    }
    return GenusKey(
      genus: data['genus'].toString(),
      name: data['name'].toString(),
      url: url,
    );
  }
}

class GenusKeyCatalog {
  static Future<List<GenusKey>>? _loading;
  static void clearCache() {
    _loading = null;
  }

  static Future<List<GenusKey>> load() => _loading ??= _read();
  static Future<List<GenusKey>> _read() async {
    try {
      final data =
          jsonDecode(
                await ScientificData.loadString(
                  'assets/italic/italic_genus_keys.json',
                ),
              )
              as Map;
      return (data['keys'] as List)
          .whereType<Map>()
          .map(GenusKey.fromMap)
          .whereType<GenusKey>()
          .toList();
    } catch (_) {
      _loading = null;
      rethrow;
    }
  }
}

class IdentificationRepository {
  final _reference = ItalicReferenceRepository();
  List<ItalicTaxon> get taxa => _reference.taxa;
  List<GenusKey> genusKeys = [];
  late IdentificationKey pilot;
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    await _reference.load();
    genusKeys = await GenusKeyCatalog.load();
    pilot = IdentificationKey.fromMap(
      Map<String, dynamic>.from(
        jsonDecode(
          await ScientificData.loadString(
            'assets/italic/flavoparmelia_key.json',
          ),
        ),
      ),
    );
    _loaded = true;
  }
}
