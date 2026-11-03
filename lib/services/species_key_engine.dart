import '../data/character_matrix_repository.dart';
import '../data/italic_api_traits_repository.dart';
import '../models/character_review.dart';
import 'physcia_review_engine.dart';
import 'structured_key_engine.dart';

enum SpeciesMatch { match, unknown, different }

class SpeciesQuestion {
  const SpeciesQuestion(
    this.id,
    this.title,
    this.prompt,
    this.help,
    this.choices, {
    this.structured,
    this.review,
  });
  final String id, title, prompt, help;
  final Map<String, String> choices;
  final StructuredQuestion? structured;
  final PilotCharacter? review;
  String label(String choice) =>
      choice == 'unknown' ? 'Non so / salta' : choices[choice] ?? choice;
}

class SpeciesCriterion {
  const SpeciesCriterion(
    this.question,
    this.selection,
    this.status,
    this.source,
    this.quote,
  );
  final SpeciesQuestion question;
  final String selection, source, quote;
  final SpeciesMatch status;
  String get label => switch (status) {
    SpeciesMatch.match => 'Corrisponde ai dati',
    SpeciesMatch.unknown => 'Da verificare · dato insufficiente o sospeso',
    SpeciesMatch.different => 'Profilo documentato diverso',
  };
}

class SpeciesCandidate {
  const SpeciesCandidate(this.row, this.criteria);
  final MatrixTaxon row;
  final List<SpeciesCriterion> criteria;
  bool get different => criteria.any((c) => c.status == SpeciesMatch.different);
  bool get uncertain =>
      criteria.isEmpty || criteria.any((c) => c.status == SpeciesMatch.unknown);
}

class SpeciesResult {
  const SpeciesResult(this.matching, this.uncertain, this.different);
  final List<SpeciesCandidate> matching, uncertain, different;
  List<SpeciesCandidate> get possible => [...matching, ...uncertain];
  bool get oneProfile => matching.length == 1 && uncertain.isEmpty;
}

/// Exploratory selection, followed by an official key. No text proposals,
/// suspect per-ascus/K API fields, or reproductive absences are admitted.
class SpeciesKeyEngine {
  SpeciesKeyEngine(this.matrix, {this.api, ReviewRegistry? registry})
    : registry = registry ?? ReviewRegistry([]),
      apiById = {
        for (final row in api?.taxa ?? <ApiTraitRow>[]) row.taxon.italicId: row,
      };
  static const id = 'species-guided-v1';
  final CharacterMatrix matrix;
  final ApiTraitsMatrix? api;
  final ReviewRegistry registry;
  final Map<int?, ApiTraitRow> apiById;
  final _structured = StructuredKey();
  List<String> get genera =>
      (matrix.taxa
          .map((r) => r.taxon.scientificName.split(' ').first)
          .toSet()
          .toList()
        ..sort());

  static final basicQuestions = [
    for (final id in [
      'growthForm',
      'substrata',
      'photobiont',
      'reproductiveStrategy',
    ])
      for (final q in StructuredKey.questions.where((q) => q.id == id))
        SpeciesQuestion(q.id, q.title, q.prompt, q.help, {
          for (final c in q.choices) c.id: c.label,
        }, structured: q),
  ];
  static const apiQuestions = [
    SpeciesQuestion(
      'api_ascocarp_form',
      'Tipo di corpi fruttiferi',
      'Quali corpi fruttiferi hai osservato?',
      'Apoteci: disco o coppa esposta. Periteci: struttura chiusa con un piccolo poro. Se non li vedi, scegli Non so: un campione sterile non dimostra che la specie sia sempre sterile.',
      {'apothecioid': 'Apoteci', 'perithecioid': 'Periteci'},
    ),
    SpeciesQuestion(
      'api_apothecia_type',
      'Margine degli apoteci',
      'Gli apoteci hanno un margine tallino?',
      'Usa questa scelta solo su apoteci riconosciuti. Non lecanorino comprende più tipi e non equivale automaticamente a lecideino.',
      {
        'lecanorine': 'Lecanorini · con margine tallino',
        'not_lecanorine': 'Non lecanorini',
      },
    ),
    SpeciesQuestion(
      'api_lirelliform',
      'Forma degli apoteci',
      'Gli apoteci sono lirelliformi?',
      'Le lirelle sono strutture allungate, simili a fessure. Se la forma non è verificabile, salta.',
      {'yes': 'Lirelliformi', 'no': 'Non lirelliformi'},
    ),
    SpeciesQuestion(
      'api_spore_colour',
      'Colore delle ascospore',
      'Al microscopio, le ascospore sono pigmentate o ialine?',
      'Confronta ascospore mature. Se non le hai osservate al microscopio, scegli Non so.',
      {'pigmented': 'Pigmentate', 'hyaline': 'Ialine / incolori'},
    ),
    SpeciesQuestion(
      'api_spore_cells',
      'Cellule delle ascospore',
      'Quante cellule hanno le ascospore mature?',
      'Il numero di cellule è distinto dal numero di spore per asco. Quest’ultimo non è usato qui perché abbiamo rilevato discrepanze nella fonte.',
      {
        'one': 'Una cellula',
        'two': 'Due cellule',
        'many': 'Più di due cellule',
      },
    ),
    SpeciesQuestion(
      'api_polarilocular',
      'Ascospore polariloculari',
      'Le ascospore sono polariloculari?',
      'Verifica al microscopio la struttura delle due cellule e del collegamento. Una spora semplicemente settata non basta.',
      {'yes': 'Polariloculari', 'no': 'Non polariloculari'},
    ),
    SpeciesQuestion(
      'api_muriform',
      'Ascospore muriformi',
      'Sono presenti setti sia trasversali sia longitudinali?',
      'Confronta ascospore mature al microscopio.',
      {'yes': 'Muriformi / submuriformi', 'no': 'Non muriformi'},
    ),
  ];
  static final reviewQuestions = [
    for (final c in PhysciaPilot.characters)
      SpeciesQuestion(
        'review:${c.id}',
        c.label,
        'Come si presenta: ${c.label.toLowerCase()}?',
        '${c.help} Questo confronto usa soltanto revisioni manuali confermate delle Physcia.',
        {
          for (final e in c.values.entries.where((e) => c.stable(e.key)))
            e.key: e.value,
        },
        review: c,
      ),
  ];
  static final allQuestions = [
    ...basicQuestions,
    ...apiQuestions,
    ...reviewQuestions,
  ];

  Map<String, String> normalize(Map<String, String> input) {
    final result = <String, String>{};
    final genus = input['_genus'];
    if (genus != null && genera.contains(genus)) result['_genus'] = genus;
    for (final entry in input.entries) {
      final found = allQuestions.where((q) => q.id == entry.key);
      if (found.isNotEmpty &&
          (entry.value == 'unknown' ||
              found.first.choices.containsKey(entry.value))) {
        result[entry.key] = entry.value;
      }
    }
    final manual = {
      for (final e in result.entries.where((e) => e.key.startsWith('review:')))
        e.key.substring(7): e.value,
    };
    for (final q in reviewQuestions) {
      if (PhysciaPilot.absentSampleParent(q.review!.id, manual) != null) {
        result.remove(q.id);
      }
    }
    if (result['api_ascocarp_form'] == 'perithecioid') {
      result.remove('api_apothecia_type');
      result.remove('api_lirelliform');
    }
    if (result['review:apothecia_type'] == 'absent') {
      result.remove('api_apothecia_type');
      result.remove('api_lirelliform');
      if (result['api_ascocarp_form'] == 'apothecioid') {
        result.remove('api_ascocarp_form');
      }
    }
    if (result['api_spore_cells'] == 'one') {
      result.remove('api_polarilocular');
      result.remove('api_muriform');
    } else if (result['api_spore_cells'] == 'many') {
      result.remove('api_polarilocular');
    }
    return result;
  }

  SpeciesCriterion criterion(
    MatrixTaxon row,
    SpeciesQuestion question,
    String selection,
  ) {
    SpeciesCriterion answer(Set<String>? values, String source, String quote) =>
        SpeciesCriterion(
          question,
          selection,
          values == null || values.isEmpty
              ? SpeciesMatch.unknown
              : values.contains(selection)
              ? SpeciesMatch.match
              : SpeciesMatch.different,
          source,
          quote,
        );
    if (question.structured != null) {
      final assessment = _structured.assess(row, {
        for (final q in StructuredKey.questions)
          q.id: q.id == question.id ? selection : 'unknown',
      });
      final c = assessment.criteria.single;
      return SpeciesCriterion(
        question,
        selection,
        switch (c.status) {
          StructuredMatch.match => SpeciesMatch.match,
          StructuredMatch.unknown => SpeciesMatch.unknown,
          StructuredMatch.different => SpeciesMatch.different,
        },
        'Codice strutturato ITALIC · ${question.id}',
        c.cell.evidence.map((e) => e.quote).join(' / '),
      );
    }
    if (question.review case final character?) {
      final absent = PhysciaPilot.absenceFor(registry, row.taxon, character.id);
      if (absent != null) {
        return answer(
          null,
          'Struttura genitrice assente o non verificata',
          absent.quote,
        );
      }
      final review = registry.latest(row.taxon.italicId!, character.id);
      if (!PhysciaPilot.usable(review, row.taxon, character)) {
        return answer(
          null,
          'Revisione manuale non disponibile o non utilizzabile',
          '',
        );
      }
      return answer(
        character.selected(review!.value).toSet(),
        'Revisione manuale · ${review.reviewer}',
        review.quote.isEmpty
            ? 'Assenza dichiarata dall’autore della revisione'
            : review.quote,
      );
    }
    // Latest manual entries shadow API values, including draft/unknown entries.
    if (question.id == 'api_apothecia_type' ||
        question.id == 'api_ascocarp_form') {
      final review = registry.latest(row.taxon.italicId!, 'apothecia_type');
      if (review != null) {
        final c = PhysciaPilot.character('apothecia_type')!;
        if (!PhysciaPilot.usable(review, row.taxon, c)) {
          return answer(null, 'Revisione manuale da completare', review.quote);
        }
        final types = c.selected(review.value);
        final mapped = <String>{};
        if (question.id == 'api_ascocarp_form') {
          if (types.any(['lecanorine', 'lecideine', 'biatorine'].contains)) {
            mapped.add('apothecioid');
          }
          return answer(
            mapped,
            'Revisione manuale · ${review.reviewer}',
            review.quote,
          );
        }
        if (types.contains('lecanorine')) mapped.add('lecanorine');
        if (types.any(['lecideine', 'biatorine'].contains)) {
          mapped.add('not_lecanorine');
        }
        return answer(
          mapped,
          'Revisione manuale · ${review.reviewer}',
          review.quote,
        );
      }
    }
    if (question.id == 'api_lirelliform' &&
        (registry.latest(row.taxon.italicId!, 'apothecia_shape') != null ||
            PhysciaPilot.absenceFor(registry, row.taxon, 'apothecia_shape') !=
                null)) {
      return answer(
        null,
        'Usa la revisione manuale della forma degli apoteci',
        '',
      );
    }
    final apiRow = apiById[row.taxon.italicId];
    if (apiRow == null ||
        apiRow.schemaIssueCount > 0 ||
        apiRow.descriptionChanged) {
      return answer(null, 'Dato API non disponibile o da aggiornare', '');
    }
    final values = apiRow.values;
    int? field(String id) =>
        apiRow.conflicts.any((c) => c.concerns(id)) ? null : values[id];
    Set<String>? options(Map<String, String> mapping) {
      final found = {
        for (final e in mapping.entries)
          if (field(e.value) == 1) e.key,
      };
      if (!found.contains(selection) &&
          mapping.values.any((id) => field(id) == null)) {
        return null;
      }
      return found.isEmpty ? null : found;
    }

    final result = switch (question.id) {
      'api_ascocarp_form' => options({
        'apothecioid': 'ascocarps_apothecioid',
        'perithecioid': 'ascocarps_perithecioid',
      }),
      'api_apothecia_type' =>
        field('ascocarps_apothecioid') != 1 ||
                field('apothecia_lecanorine') == null
            ? null
            : {
                field('apothecia_lecanorine') == 1
                    ? 'lecanorine'
                    : 'not_lecanorine',
              },
      'api_lirelliform' =>
        field('ascocarps_apothecioid') != 1 ||
                field('apothecia_lirelliform') == null
            ? null
            : {field('apothecia_lirelliform') == 1 ? 'yes' : 'no'},
      'api_spore_colour' => options({
        'pigmented': 'ascospores_pigmented',
        'hyaline': 'ascospores_hyaline',
      }),
      'api_spore_cells' => options({
        'one': 'ascospores_1-celled',
        'two': 'ascospores_2-celled',
        'many': 'ascospores_more_than_2-celled',
      }),
      'api_polarilocular' =>
        field('ascospores_2-celled') != 1 ||
                field('ascospores_polarilocular') == null
            ? null
            : {field('ascospores_polarilocular') == 1 ? 'yes' : 'no'},
      'api_muriform' =>
        ![
                  'ascospores_1-celled',
                  'ascospores_2-celled',
                  'ascospores_more_than_2-celled',
                ].any((id) => field(id) == 1) ||
                field('ascospores_muriform_or_submuriform') == null
            ? null
            : {field('ascospores_muriform_or_submuriform') == 1 ? 'yes' : 'no'},
      _ => null,
    };
    return answer(
      result,
      'Traits ITALIC API · confronto da verificare',
      '${apiRow.sourceUrl}\nStati documentati: ${result?.join(' / ') ?? 'non disponibili'}',
    );
  }

  SpeciesResult evaluate(Map<String, String> input) {
    final selections = normalize(input);
    final matching = <SpeciesCandidate>[],
        uncertain = <SpeciesCandidate>[],
        different = <SpeciesCandidate>[];
    for (final row in matrix.taxa) {
      if (selections['_genus'] != null &&
          row.taxon.scientificName.split(' ').first != selections['_genus']) {
        continue;
      }
      final criteria = <SpeciesCriterion>[];
      for (final q in allQuestions) {
        final choice = selections[q.id];
        if (choice == null || choice == 'unknown') continue;
        criteria.add(criterion(row, q, choice));
      }
      final candidate = SpeciesCandidate(row, criteria);
      if (candidate.different) {
        different.add(candidate);
      } else if (candidate.uncertain) {
        uncertain.add(candidate);
      } else {
        matching.add(candidate);
      }
    }
    return SpeciesResult(matching, uncertain, different);
  }

  List<SpeciesQuestion> available(
    Map<String, String> selections,
    SpeciesResult result,
  ) {
    final possible = result.possible;
    final pool = [
      ...basicQuestions,
      ...apiQuestions,
      if (possible.isNotEmpty &&
          possible.every((r) => PhysciaPilot.inScope(r.row.taxon)))
        ...reviewQuestions,
    ];
    return pool
        .where(
          (q) =>
              !selections.containsKey(q.id) &&
              normalize({
                ...selections,
                q.id: q.choices.keys.first,
              }).containsKey(q.id),
        )
        .toList();
  }

  double score(SpeciesQuestion q, SpeciesResult result) {
    var sum = 0.0;
    final possible = result.possible;
    if (possible.length < 2) return 0;
    for (final choice in q.choices.keys) {
      var yes = 0, no = 0;
      for (final candidate in possible) {
        final status = criterion(candidate.row, q, choice).status;
        if (status == SpeciesMatch.match) yes++;
        if (status == SpeciesMatch.different) no++;
      }
      sum += yes * no / (possible.length * possible.length);
    }
    return sum;
  }

  SpeciesQuestion? next(Map<String, String> selections, SpeciesResult result) {
    final choices = available(selections, result);
    for (final q in choices.where((q) => q.structured != null)) {
      if (score(q, result) > 0) return q;
    }
    SpeciesQuestion? best;
    var maximum = 0.0;
    for (final q in choices.where((q) => q.structured == null)) {
      final value = score(q, result);
      if (value > maximum) {
        maximum = value;
        best = q;
      }
    }
    return best;
  }
}
