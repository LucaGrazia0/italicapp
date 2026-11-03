import 'package:flutter_test/flutter_test.dart';
import 'package:italicapp/data/italic_reference_repository.dart';
import 'package:italicapp/services/ecological_compatibility_engine.dart';
import 'package:italicapp/models/ecological_scale.dart';
import 'dart:convert';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final engine = EcologicalCompatibilityEngine();
  const query = EcologicalQuery(
    region: 'Emilia-Romagna',
    belt: 'Montane belt',
    substrate: 'Roccia',
    growthForm: 'Crostoso',
  );

  test('Regione non citata non equivale a incompatibilità', () {
    final taxon = ItalicTaxon(
      scientificName: 'Taxon A',
      distribution: 'N - Lomb (autore 2000).',
      belts: {'Montane belt': 'common'},
      substrata: 'rocks',
      growthForm: 'Crustose',
    );
    final a = engine.evaluate(taxon, query);
    expect(a.notDocumented, 1);
    expect(a.incompatible, 0);
    expect(a.compatible, 3);
    expect(a.evaluated, 3);
    expect(a.score, 100);
  });

  test('Presenza documentata e parentesi nelle citazioni', () {
    final taxon = ItalicTaxon(
      scientificName: 'Taxon B',
      distribution: 'N - Emil (Rossi (2020)), Lomb.',
      belts: {'Montane belt': 'rare'},
      substrata: 'rocks',
      growthForm: 'Crustose',
    );
    final a = engine.evaluate(taxon, query);
    expect(a.compatible, 4);
    expect(a.notDocumented, 0);
  });

  test('Fascia absent separata dal dato mancante', () {
    final absent = ItalicTaxon(
      scientificName: 'Taxon C',
      belts: {'Montane belt': 'absent'},
    );
    final missing = ItalicTaxon(scientificName: 'Taxon D');
    expect(
      engine
          .evaluate(absent, const EcologicalQuery(belt: 'Montane belt'))
          .reportedAbsent,
      1,
    );
    expect(
      engine
          .evaluate(missing, const EcologicalQuery(belt: 'Montane belt'))
          .unknown,
      1,
    );
  });

  test('Substrato incompatibile resta incompatibile', () {
    final taxon = ItalicTaxon(
      scientificName: 'Taxon E',
      substrata: 'bark',
      growthForm: 'Crustose',
    );
    final a = engine.evaluate(
      taxon,
      const EcologicalQuery(substrate: 'Roccia', growthForm: 'Crostoso'),
    );
    expect(a.incompatible, 1);
    expect(a.compatible, 1);
    expect(a.score, 50);
  });

  test('Nessun criterio valutabile non produce punteggio', () {
    final a = engine.evaluate(
      const ItalicTaxon(scientificName: 'Taxon F'),
      query,
    );
    expect(a.score, isNull);
    expect(a.unknown, 4);
  });

  for (final scale in EcologicalScaleDefinition.all) {
    test('${scale.label}: estremi inclusi e dato mancante distinto', () {
      final taxon = ItalicTaxon(
        scientificName: 'Range test',
        ecologicalScales: {
          scale.key: {'min': scale.min, 'max': scale.min + 1},
        },
      );
      for (final value in [scale.min, scale.min + 1]) {
        final a = engine.evaluate(
          taxon,
          EcologicalQuery(scales: {scale.key: value}),
        );
        expect(a.compatible, 1);
        expect(a.requested, 1);
      }
      expect(
        engine
            .evaluate(taxon, EcologicalQuery(scales: {scale.key: scale.max}))
            .incompatible,
        1,
      );
      expect(
        engine
            .evaluate(
              const ItalicTaxon(scientificName: 'Missing'),
              EcologicalQuery(scales: {scale.key: scale.min}),
            )
            .unknown,
        1,
      );
    });
  }

  test('Zero di poleotolleranza è un valore valido', () {
    const taxon = ItalicTaxon(
      scientificName: 'Zero',
      ecologicalScales: {
        'Poleotolerance': {'min': 0, 'max': 0},
      },
    );
    final a = engine.evaluate(
      taxon,
      const EcologicalQuery(scales: {'Poleotolerance': 0}),
    );
    expect(a.score, 100);
    expect(a.evaluated, 1);
  });

  test(
    'Intervalli invalidi e selezioni fuori scala restano non valutabili',
    () {
      for (final value in [
        {'min': 4, 'max': 1},
        {'min': -1, 'max': 2},
        {'min': 1.5, 'max': 2},
        {'min': '1', 'max': 3},
      ]) {
        final a = engine.evaluate(
          ItalicTaxon(
            scientificName: 'Bad data',
            ecologicalScales: {'Aridity': value},
          ),
          const EcologicalQuery(scales: {'Aridity': 2}),
        );
        expect(a.score, isNull);
        expect(a.unknown, 1);
      }
      final a = engine.evaluate(
        const ItalicTaxon(
          scientificName: 'Bad query',
          ecologicalScales: {
            'Aridity': {'min': 1, 'max': 5},
          },
        ),
        const EcologicalQuery(scales: {'Aridity': 9}),
      );
      expect(a.unknown, 1);
    },
  );

  test('Codici misti conservano entrambi i fotobionti e le strategie', () {
    const taxon = ItalicTaxon(
      scientificName: 'Mixed',
      ecologyCodes: {
        'photobiont': 'Ch-Cy.h',
        'reproductiveStrategy': 'S-A.s',
        'substrata': 'Epiph-Sax',
        'growthForm': 'Cr.pl',
      },
    );
    expect(
      engine
          .evaluate(
            taxon,
            const EcologicalQuery(
              photobiont: 'Ch',
              reproductiveStrategy: 'S',
              substrate: 'Roccia',
              growthForm: 'Crostoso',
            ),
          )
          .compatible,
      4,
    );
    expect(
      engine
          .evaluate(
            taxon,
            const EcologicalQuery(
              photobiont: 'Cy.h',
              reproductiveStrategy: 'A.s',
              substrate: 'Corteccia',
            ),
          )
          .compatible,
      3,
    );
    expect(
      engine
          .evaluate(
            taxon,
            const EcologicalQuery(
              photobiont: 'Tr',
              reproductiveStrategy: 'A.i',
            ),
          )
          .incompatible,
      2,
    );
  });

  test(
    'F non include Fol o Frut e codici vuoti non diventano incompatibilità',
    () {
      expect(
        EcologicalCompatibilityEngine.growthMatch(
          const ItalicTaxon(
            scientificName: 'Foliose',
            ecologyCodes: {'growthForm': 'Fol.b'},
          ),
          'Non lichenizzato',
        ),
        false,
      );
      expect(
        EcologicalCompatibilityEngine.substrateMatch(
          const ItalicTaxon(
            scientificName: 'Unknown',
            ecologyCodes: {'substrata': ''},
            substrata: 'rocks',
          ),
          'Roccia',
        ),
        isNull,
      );
    },
  );

  test(
    'Fascia reportedAbsent conta tra i criteri valutabili e riduce il punteggio',
    () {
      final a = engine.evaluate(
        const ItalicTaxon(
          scientificName: 'Absent',
          belts: {'Montane belt': 'absent'},
          substrata: 'rocks',
        ),
        const EcologicalQuery(belt: 'Montane belt', substrate: 'Roccia'),
      );
      expect(a.score, 50);
      expect(a.evaluated, 2);
      expect(a.coverage, 1);
      expect(a.reportedAbsent, 1);
    },
  );

  test(
    'La classifica preferisce più evidenze a un 100% con molti dati mancanti',
    () {
      final sparse = engine.evaluate(
        const ItalicTaxon(scientificName: 'Sparse', substrata: 'rocks'),
        query,
      );
      final supported = engine.evaluate(
        const ItalicTaxon(
          scientificName: 'Supported',
          substrata: 'rocks',
          growthForm: 'Crustose',
          belts: {'Montane belt': 'absent'},
        ),
        query,
      );
      expect(sparse.score, 100);
      expect(supported.score, 67);
      expect(
        EcologicalCompatibilityEngine.compare(supported, sparse),
        lessThan(0),
      );
    },
  );

  test(
    'Dataset reale: tutti i sei criteri e le descrizioni sono disponibili per ID 1',
    () async {
      final data =
          jsonDecode(
                await rootBundle.loadString(
                  'assets/italic/italic_checklist.json',
                ),
              )
              as Map;
      final taxa = (data['taxa'] as List).cast<Map>();
      expect(taxa.length, 3588);
      final taxon = ItalicTaxon.fromMap(
        Map<String, dynamic>.from(taxa.singleWhere((t) => t['italicId'] == 1)),
      );
      expect(taxon.description, isNotEmpty);
      final a = engine.evaluate(
        taxon,
        const EcologicalQuery(
          scales: {
            'pH of the substrata': 1,
            'Solar irradiation': 3,
            'Aridity': 2,
            'Eutrophication': 1,
            'Altitudinal distribution': 4,
            'Poleotolerance': 1,
          },
        ),
      );
      expect(a.compatible, 6);
      expect(a.evaluated, 6);
      expect(a.score, 100);
      expect(
        taxa.where((t) => [3629, 3630, 3631].contains(t['italicId'])).length,
        3,
      );
    },
  );
}
