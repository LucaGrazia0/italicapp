import 'dart:convert';
import 'scientific_data.dart';
import '../services/character_dictionary.dart';
import 'revision_cache.dart';

class CharacterDictionaryRepository {
  static final _cache = RevisionCache<CharacterDictionary>();
  Future<CharacterDictionary> load({int? revision}) => _cache.load(
    (key) async => CharacterDictionary.fromMap(
      jsonDecode(
            await ScientificData.loadString(
              'assets/italic/character_dictionary_v3.json',
              revision: key,
            ),
          )
          as Map,
    ),
    revision: revision,
  );
}
