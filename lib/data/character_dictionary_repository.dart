import 'dart:convert';
import 'scientific_data.dart';
import '../services/character_dictionary.dart';

class CharacterDictionaryRepository {
  Future<CharacterDictionary> load() async => CharacterDictionary.fromMap(
    jsonDecode(
          await ScientificData.loadString(
            'assets/italic/character_dictionary_v3.json',
          ),
        )
        as Map,
  );
}
