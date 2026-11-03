import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:italicapp/data/identification_repository.dart';
import 'package:italicapp/data/italic_reference_repository.dart';
import 'package:italicapp/data/observation_repository.dart';
import 'package:italicapp/models/identification_path.dart';
import 'package:italicapp/models/observation.dart';
import 'package:italicapp/services/identification_engine.dart';

void main() {
  final key = IdentificationKey.fromMap(
    jsonDecode(File('assets/italic/flavoparmelia_key.json').readAsStringSync()),
  );
  final taxa =
      (jsonDecode(
                File('assets/italic/italic_checklist.json').readAsStringSync(),
              )['taxa']
              as List)
          .map((t) => ItalicTaxon.fromMap(Map<String, dynamic>.from(t)))
          .toList();
  final engine = IdentificationEngine();

  test(
    'Ogni stato del prototipo ha una citazione presente nella descrizione',
    () {
      expect(key.coveredTaxa, [978, 979]);
      for (final question in key.questions) {
        for (final id in key.coveredTaxa) {
          final taxon = taxa.singleWhere((t) => t.italicId == id);
          expect(taxon.description, contains(question.evidence[id]));
          expect(question.documentedAnswer(taxon), isNotNull);
        }
      }
      expect(key.questions.last.evidence[978], startsWith('medulla K+'));
      expect(key.questions.last.evidence[978], isNot(contains('K-')));
    },
  );

  test('Due rami concordanti distinguono i due candidati documentati', () {
    for (final entry in {KeyAnswer.a: 978, KeyAnswer.b: 979}.entries) {
      final result = engine.evaluate(taxa, key, {
        'soredia': entry.key,
        'medulla_k': entry.key,
      });
      expect(result.supported.map((t) => t.italicId), [entry.value]);
      expect(result.excluded, 1);
      expect(result.unresolved, isEmpty);
    }
  });

  test('Caratteri discordanti non forzano una specie', () {
    final result = engine.evaluate(taxa, key, {
      'soredia': KeyAnswer.a,
      'medulla_k': KeyAnswer.b,
    });
    expect(result.supported, isEmpty);
    expect(result.unresolved, isEmpty);
    expect(result.excluded, 2);
    expect(result.excludedTaxa.map((t) => t.italicId).toSet(), {978, 979});
  });

  test(
    'Non so lascia entrambe le specie e non conta come carattere osservato',
    () {
      final result = engine.evaluate(taxa, key, {
        'soredia': KeyAnswer.unknown,
        'medulla_k': KeyAnswer.unknown,
      });
      expect(result.activeCriteria, 0);
      expect(result.supported, isEmpty);
      expect(result.unresolved.map((t) => t.italicId).toSet(), {978, 979});
      expect(result.excluded, 0);
    },
  );

  test('Descrizioni cambiate e nuovi taxa restano non valutabili', () {
    final unknown = [
      const ItalicTaxon(
        scientificName: 'Flavoparmelia caperata (L.) Hale',
        italicId: 978,
        description: 'Changed',
      ),
      const ItalicTaxon(
        scientificName: 'Flavoparmelia new_taxon',
        italicId: 99999,
      ),
      const ItalicTaxon(scientificName: 'Other genus', italicId: 4),
    ];
    final result = engine.evaluate(unknown, key, {'soredia': KeyAnswer.a});
    expect(result.supported, isEmpty);
    expect(result.unresolved.length, 2);
    expect(result.excluded, 0);
  });

  test('Macrocaratteri: la forma non documentata non diventa assenza', () {
    final result = engine.evaluate(
      [
        const ItalicTaxon(
          scientificName: 'Crust',
          ecologyCodes: {'growthForm': 'Cr.pl'},
        ),
        const ItalicTaxon(
          scientificName: 'Leaf',
          ecologyCodes: {'growthForm': 'Fol.b'},
        ),
        const ItalicTaxon(
          scientificName: 'Fungus',
          ecologyCodes: {'growthForm': 'LF'},
        ),
        const ItalicTaxon(
          scientificName: 'Unknown',
          ecologyCodes: {'growthForm': ''},
        ),
      ],
      IdentificationKey.macro,
      {'crustose': KeyAnswer.b, 'foliose': KeyAnswer.a},
    );
    expect(result.supported.single.scientificName, 'Leaf');
    expect(result.unresolved.length, 2);
    expect(result.excluded, 1);
  });

  test(
    'Un ramo positivo termina il macropercorso e scarta risposte successive',
    () {
      const macro = IdentificationKey.macro;
      expect(
        macro.normalize({'crustose': KeyAnswer.a, 'foliose': KeyAnswer.b}),
        {'crustose': KeyAnswer.a},
      );
      expect(macro.next({'crustose': KeyAnswer.a}), isNull);
      expect(macro.next({'crustose': KeyAnswer.unknown})?.id, 'foliose');
      expect(macro.normalize({'foliose': KeyAnswer.a}), isEmpty);
    },
  );

  test('Osservazioni precedenti e percorsi danneggiati restano leggibili', () {
    final original = _observation().toMap()..remove('identificationPath');
    expect(Observation.fromMap(original).identificationPath, isNull);
    original['identificationPath'] = {
      'keyId': key.id,
      'answers': 'invalid',
      'savedAt': 'bad',
    };
    expect(Observation.fromMap(original).identificationPath, isNull);
    final path = IdentificationPath.fromMap({
      'keyId': key.id,
      'answers': {'soredia': 'a', 'invalid': 'invented'},
      'savedAt': '2026-10-20T10:00:00Z',
    });
    expect(path!.answers, {'soredia': KeyAnswer.a});
  });

  test(
    'Archivio osservazioni: il percorso persiste con foto, GPS e identificazione invariati',
    () async {
      final repository = ObservationRepository(factory: newIdbFactoryMemory());
      final observation = _observation();
      observation.identificationPath = IdentificationPath(
        keyId: key.id,
        answers: {'soredia': KeyAnswer.a, 'medulla_k': KeyAnswer.unknown},
        savedAt: DateTime.utc(2026, 10, 20),
      );
      await repository.save(observation);
      final restored = (await repository.all()).single;
      expect(
        restored.identificationPath!.toMap(),
        observation.identificationPath!.toMap(),
      );
      expect(restored.photoBytes, orderedEquals([1, 2, 3]));
      expect(restored.latitude, observation.latitude);
      expect(restored.horizontalAccuracy, 5);
      expect(restored.notes, 'Field notes');
      expect(restored.rank, IdentificationRank.undetermined);
      expect(restored.taxonName, isNull);
    },
  );

  test(
    'I 509 collegamenti sono ufficiali e i generi con più chiavi sono conservati',
    () {
      final data = jsonDecode(
        File('assets/italic/italic_genus_keys.json').readAsStringSync(),
      );
      final entries = (data['keys'] as List)
          .map((r) => GenusKey.fromMap(r))
          .toList();
      expect(entries.length, 509);
      expect(entries.every((entry) => entry != null), true);
      expect(
        entries.where((entry) => entry!.genus == 'Caloplaca').length,
        greaterThan(1),
      );
      expect(GenusKey.fromMap({'url': 'javascript:alert(1)'}), isNull);
      expect(
        GenusKey.fromMap({
          'url':
              'https://example.com/flora/index.php?key_id=1&procedure=ext_key_home',
        }),
        isNull,
      );
    },
  );
}

Observation _observation() => Observation(
  id: 'test-observation',
  createdAt: DateTime.utc(2026, 10, 20),
  latitude: 45,
  longitude: 10,
  horizontalAccuracy: 5,
  notes: 'Field notes',
  photoBytes: Uint8List.fromList([1, 2, 3]),
);
