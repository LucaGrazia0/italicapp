import '../data/character_matrix_repository.dart';

class StructuredChoice {
  const StructuredChoice(this.id, this.label, this.sourceValues);
  final String id, label;
  final Set<String> sourceValues;
}

class StructuredQuestion {
  const StructuredQuestion(
    this.id,
    this.title,
    this.prompt,
    this.help,
    this.choices, {
    this.notDocumented = false,
  });
  final String id, title, prompt, help;
  final List<StructuredChoice> choices;
  final bool notDocumented;
  StructuredChoice? choice(String value) {
    for (final choice in choices) {
      if (choice.id == value) return choice;
    }
    return null;
  }

  String label(String value) => value == StructuredKey.unknown
      ? 'Non so / Non verificato'
      : choice(value)?.label ?? 'Risposta non valida';
}

enum StructuredMatch { match, unknown, different }

class StructuredCriterion {
  const StructuredCriterion(
    this.question,
    this.selection,
    this.cell,
    this.status,
  );
  final StructuredQuestion question;
  final String selection;
  final CharacterCell cell;
  final StructuredMatch status;
  String get label => switch (status) {
    StructuredMatch.match => 'Corrisponde al profilo',
    StructuredMatch.unknown => 'Dato non disponibile o non verificabile',
    StructuredMatch.different =>
      question.notDocumented
          ? 'Substrato non documentato'
          : 'Profilo documentato diverso',
  };
}

class StructuredAssessment {
  const StructuredAssessment(this.row, this.criteria);
  final MatrixTaxon row;
  final List<StructuredCriterion> criteria;
  bool get differs =>
      criteria.any((c) => c.status == StructuredMatch.different);
  bool get uncertain =>
      criteria.isEmpty ||
      criteria.any((c) => c.status == StructuredMatch.unknown);
}

class StructuredResult {
  const StructuredResult(
    this.matching,
    this.uncertain,
    this.different,
    this.activeCriteria,
  );
  final List<StructuredAssessment> matching, uncertain, different;
  final int activeCriteria;
}

/// Only these four structured matrix columns are admitted. Description patterns
/// and the unreviewed morphology/chemistry columns cannot influence this path.
class StructuredKey {
  static const id = 'structured-v1';
  static const unknown = 'unknown';
  static const questions = [
    StructuredQuestion(
      'growthForm',
      'Forma di crescita / tipo biologico',
      'Qual è la forma principale del tallo o il tipo biologico?',
      'Scegli la forma principale. Fungo lichenicolo e non lichenizzato sono tipi biologici, non forme del tallo. Se il campione è dubbio, scegli Non so.',
      [
        StructuredChoice('Cr', 'Crostoso', {'Cr', 'Cr.pl', 'Cr.end'}),
        StructuredChoice('Fol', 'Foglioso', {'Fol', 'Fol.b', 'Fol.n', 'Fol.u'}),
        StructuredChoice('Frut', 'Fruticoso', {'Frut', 'Frut.f'}),
        StructuredChoice('Sq', 'Squamuloso', {'Sq'}),
        StructuredChoice('Lepr', 'Leproso', {'Lepr'}),
        StructuredChoice('LF', 'Fungo lichenicolo', {'LF'}),
        StructuredChoice('F', 'Non lichenizzato', {'F'}),
      ],
    ),
    StructuredQuestion(
      'photobiont',
      'Fotobionte',
      'Quale fotobionte hai riconosciuto?',
      'Se non hai verificato il fotobionte, scegli Non so. Un gruppo può essere documentato come principale o secondario; la scelta combinata richiede entrambi.',
      [
        StructuredChoice('Ch', 'Alghe verdi diverse da Trentepohlia', {
          'Ch',
          'Ch-Cy.h',
        }),
        StructuredChoice('Tr', 'Trentepohlia', {'Tr'}),
        StructuredChoice('Cy.h', 'Cianobatteri filamentosi', {
          'Cy.h',
          'Ch-Cy.h',
        }),
        StructuredChoice('Cy.c', 'Cianobatteri coccoidi', {'Cy.c'}),
        StructuredChoice(
          'Ch-Cy.h',
          'Alghe verdi con cianobatteri filamentosi secondari',
          {'Ch-Cy.h'},
        ),
      ],
    ),
    StructuredQuestion(
      'reproductiveStrategy',
      'Strategia riproduttiva prevalente',
      'Quale strategia riproduttiva prevalente puoi confrontare?',
      'Il confronto riguarda la strategia prevalente codificata da ITALIC, anche mista. Un singolo apotecio o la presenza di soredi non dimostrano la prevalenza. Se non è nota, scegli Non so. Nessuna scelta implica l’assenza delle altre strutture.',
      [
        StructuredChoice('S', 'Sessuata, anche in strategie miste', {
          'S',
          'S-A.s',
          'S-A.c',
        }),
        StructuredChoice('A.s', 'Asessuata tramite soredi o strutture simili', {
          'A.s',
          'S-A.s',
        }),
        StructuredChoice('A.i', 'Asessuata tramite isidi o strutture simili', {
          'A.i',
        }),
        StructuredChoice('A.f', 'Frammentazione del tallo', {'A.f'}),
        StructuredChoice(
          'A.c',
          'Conidi e talloconidi, anche in strategie miste',
          {'A.c', 'S-A.c'},
        ),
      ],
    ),
    StructuredQuestion(
      'substrata',
      'Substrati documentati',
      'Su quale substrato cresce il campione?',
      'Confrontiamo i substrati documentati, anche multipli. Un substrato non elencato resta non documentato: non prova un’assenza assoluta. I dati del diario non vengono selezionati automaticamente.',
      [
        StructuredChoice('Sax', 'Roccia', {'Sax'}),
        StructuredChoice('Epiph', 'Corteccia', {'Epiph'}),
        StructuredChoice('Lign', 'Legno', {'Lign'}),
        StructuredChoice('Terr', 'Suolo, muschi terricoli e detriti vegetali', {
          'Terr',
        }),
        StructuredChoice('Foliic', 'Foglie', {'Foliic'}),
      ],
      notDocumented: true,
    ),
  ];

  Map<String, String> normalize(Map<String, String> input) {
    final result = <String, String>{};
    for (final question in questions) {
      final value = input[question.id];
      if (value == null ||
          (value != unknown && question.choice(value) == null)) {
        break;
      }
      result[question.id] = value;
    }
    return result;
  }

  StructuredQuestion? next(Map<String, String> input) {
    final selections = normalize(input);
    return selections.length == questions.length
        ? null
        : questions[selections.length];
  }

  StructuredAssessment assess(MatrixTaxon row, Map<String, String> input) {
    final selections = normalize(input);
    final criteria = <StructuredCriterion>[];
    for (final question in questions) {
      final selection = selections[question.id];
      if (selection == null || selection == unknown) continue;
      final cell = row.cell(question.id);
      final allowed = question.choices
          .expand((choice) => choice.sourceValues)
          .toSet();
      final raw = row.taxon.ecologyCodes[question.id];
      final sourceValues = raw == null || raw.isEmpty
          ? <String>[]
          : question.id == 'substrata'
          ? raw.split('-')
          : [raw];
      final valid =
          sourceValues.isNotEmpty &&
          cell.values.length == sourceValues.length &&
          cell.values.every(sourceValues.contains) &&
          cell.isStructured &&
          cell.status == 'recorded' &&
          cell.values.isNotEmpty &&
          cell.values.every(allowed.contains) &&
          cell.evidence.isNotEmpty &&
          cell.evidence.every(
            (e) =>
                e.field == 'ecologyCodes.${question.id}' &&
                e.matches(row.taxon),
          );
      final status = !valid
          ? StructuredMatch.unknown
          : cell.values.any(question.choice(selection)!.sourceValues.contains)
          ? StructuredMatch.match
          : StructuredMatch.different;
      criteria.add(StructuredCriterion(question, selection, cell, status));
    }
    return StructuredAssessment(row, criteria);
  }

  StructuredResult evaluate(CharacterMatrix matrix, Map<String, String> input) {
    final selections = normalize(input);
    final matching = <StructuredAssessment>[],
        uncertain = <StructuredAssessment>[],
        different = <StructuredAssessment>[];
    for (final row in matrix.taxa) {
      final assessment = assess(row, selections);
      if (assessment.differs) {
        different.add(assessment);
      } else if (assessment.uncertain) {
        uncertain.add(assessment);
      } else {
        matching.add(assessment);
      }
    }
    return StructuredResult(
      matching,
      uncertain,
      different,
      selections.values.where((v) => v != unknown).length,
    );
  }
}
