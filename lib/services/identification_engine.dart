import '../data/italic_reference_repository.dart';
import '../models/identification_path.dart';

class KeyQuestion {
  const KeyQuestion({
    required this.id,
    required this.title,
    required this.prompt,
    required this.a,
    required this.b,
    this.help = '',
    this.growthCode,
    this.states = const {},
    this.evidence = const {},
  });

  final String id, title, prompt, a, b, help;
  final String? growthCode;
  final Map<int, KeyAnswer> states;
  final Map<int, String> evidence;

  factory KeyQuestion.fromMap(Map<String, dynamic> data) => KeyQuestion(
    id: data['id'],
    title: data['title'],
    prompt: data['prompt'],
    a: data['a'],
    b: data['b'],
    help: data['help'] ?? '',
    states: (data['states'] as Map).map(
      (k, v) => MapEntry(
        int.parse(k.toString()),
        KeyAnswer.values.byName(v.toString()),
      ),
    ),
    evidence: (data['evidence'] as Map).map(
      (k, v) => MapEntry(int.parse(k.toString()), v.toString()),
    ),
  );

  KeyAnswer? documentedAnswer(ItalicTaxon taxon) {
    if (growthCode != null) {
      var code = taxon.ecologyCodes['growthForm'];
      if (code == null) {
        final form = (taxon.growthForm ?? '').toLowerCase();
        const labels = {
          'crustose': 'Cr',
          'foliose': 'Fol',
          'fruticose': 'Frut',
          'squamulose': 'Sq',
          'leprose': 'Lepr',
        };
        for (final entry in labels.entries) {
          if (form.startsWith(entry.key)) {
            code = entry.value;
            break;
          }
        }
      }
      final group = code?.split('.').first;
      // F and LF describe fungal lifestyles, not a documented thallus form.
      if (!const ['Cr', 'Fol', 'Frut', 'Sq', 'Lepr'].contains(group)) {
        return null;
      }
      return group == growthCode ? KeyAnswer.a : KeyAnswer.b;
    }
    final quote = evidence[taxon.italicId];
    if (quote == null ||
        quote.isEmpty ||
        !(taxon.description ?? '').contains(quote)) {
      return null;
    }
    return states[taxon.italicId];
  }

  String label(KeyAnswer answer) => switch (answer) {
    KeyAnswer.a => a,
    KeyAnswer.b => b,
    KeyAnswer.unknown => 'Non so / Non verificato',
  };
}

class IdentificationKey {
  const IdentificationKey({
    required this.id,
    required this.title,
    required this.scope,
    required this.questions,
    this.genus,
    this.coveredTaxa = const [],
  });

  final String id, title, scope;
  final String? genus;
  final List<int> coveredTaxa;
  final List<KeyQuestion> questions;
  bool get isMacro => genus == null;

  factory IdentificationKey.fromMap(Map<String, dynamic> data) =>
      IdentificationKey(
        id: data['id'],
        title: data['title'],
        scope: data['scope'],
        genus: data['genus'],
        coveredTaxa: (data['covered_taxa'] as List).cast<int>(),
        questions: (data['questions'] as List)
            .map((q) => KeyQuestion.fromMap(Map<String, dynamic>.from(q)))
            .toList(),
      );

  static const macro = IdentificationKey(
    id: 'macro-v1',
    title: 'Macrocaratteri',
    scope:
        'Percorso preliminare basato sulla forma principale del tallo. '
        'Riduce i candidati della checklist; i dati non documentati restano separati e consultabili.',
    questions: [
      KeyQuestion(
        id: 'crustose',
        title: 'Tallo crostoso',
        growthCode: 'Cr',
        prompt: 'La forma principale del tallo è crostosa?',
        a: 'Sì, crostoso',
        b: 'No, altra forma',
        help:
            'Tallo aderente al substrato come una crosta; comprende le forme endolitiche e placodiomorfe. Se la forma è incerta, scegli Non so.',
      ),
      KeyQuestion(
        id: 'foliose',
        title: 'Tallo foglioso',
        growthCode: 'Fol',
        prompt: 'La forma principale del tallo è fogliosa?',
        a: 'Sì, foglioso',
        b: 'No, altra forma',
        help:
            'Tallo formato da lobi appiattiti; comprende le forme ombelicate. Considera la forma principale, non un singolo margine sollevato.',
      ),
      KeyQuestion(
        id: 'fruticose',
        title: 'Tallo fruticoso',
        growthCode: 'Frut',
        prompt: 'La forma principale del tallo è fruticosa?',
        a: 'Sì, fruticoso',
        b: 'No, altra forma',
        help:
            'Tallo a cespuglietto o filamenti, eretto o pendente. Se il campione presenta forme diverse e non riesci a scegliere, usa Non so.',
      ),
      KeyQuestion(
        id: 'squamulose',
        title: 'Tallo squamuloso',
        growthCode: 'Sq',
        prompt: 'La forma principale del tallo è squamulosa?',
        a: 'Sì, squamuloso',
        b: 'No, altra forma',
        help: 'Tallo formato principalmente da piccole squamule.',
      ),
      KeyQuestion(
        id: 'leprose',
        title: 'Tallo leproso',
        growthCode: 'Lepr',
        prompt: 'La forma principale del tallo è leprosa?',
        a: 'Sì, leproso',
        b: 'No, altra forma',
        help:
            'Tallo con aspetto prevalentemente polverulento o granuloso. La presenza di soredi su un tallo foglioso non ne cambia automaticamente la forma principale.',
      ),
    ],
  );

  /// Ignore stale answers after a changed branch or an unanswered question.
  Map<String, KeyAnswer> normalize(Map<String, KeyAnswer> input) {
    final output = <String, KeyAnswer>{};
    for (final question in questions) {
      final answer = input[question.id];
      if (answer == null) break;
      output[question.id] = answer;
      if (isMacro && answer == KeyAnswer.a) break;
    }
    return output;
  }

  KeyQuestion? next(Map<String, KeyAnswer> input) {
    final answers = normalize(input);
    for (final question in questions) {
      final answer = answers[question.id];
      if (answer == null) return question;
      if (isMacro && answer == KeyAnswer.a) return null;
    }
    return null;
  }
}

class IdentificationResult {
  const IdentificationResult(
    this.supported,
    this.unresolved,
    this.excludedTaxa,
    this.activeCriteria,
  );
  final List<ItalicTaxon> supported, unresolved, excludedTaxa;
  final int activeCriteria;
  int get excluded => excludedTaxa.length;
}

class IdentificationEngine {
  IdentificationResult evaluate(
    List<ItalicTaxon> taxa,
    IdentificationKey key,
    Map<String, KeyAnswer> input,
  ) {
    final answers = key.normalize(input);
    final active = answers.values.where((a) => a != KeyAnswer.unknown).length;
    final supported = <ItalicTaxon>[];
    final unresolved = <ItalicTaxon>[];
    final excluded = <ItalicTaxon>[];
    for (final taxon in taxa) {
      if (key.genus != null &&
          taxon.scientificName.split(' ').first != key.genus) {
        continue;
      }
      var unknown = active == 0;
      var conflict = false;
      for (final question in key.questions) {
        final answer = answers[question.id];
        if (answer == null || answer == KeyAnswer.unknown) continue;
        final documented = question.documentedAnswer(taxon);
        if (documented == null) {
          unknown = true;
        } else if (documented != answer) {
          conflict = true;
          break;
        }
      }
      if (conflict) {
        excluded.add(taxon);
      } else if (unknown) {
        unresolved.add(taxon);
      } else {
        supported.add(taxon);
      }
    }
    return IdentificationResult(supported, unresolved, excluded, active);
  }
}
