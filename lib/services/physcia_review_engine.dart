import '../data/character_matrix_repository.dart';
import '../data/italic_reference_repository.dart';
import '../models/character_review.dart';
import 'character_dictionary.dart';

class PilotCharacter {
  const PilotCharacter(
    this.id,
    this.label,
    this.values,
    this.help, {
    this.multiple = false,
  });
  final String id, label, help;
  final Map<String, String> values;
  final bool multiple;
  List<String> selected(String value) => value.split('|');
  bool validValue(String? value) {
    if (value == null) return false;
    if (values.containsKey(value)) return true;
    final parts = selected(value);
    return multiple &&
        parts.length > 1 &&
        parts.toSet().length == parts.length &&
        parts.every(
          (v) =>
              values.containsKey(v) &&
              !['unknown', 'variable', 'other', 'absent'].contains(v),
        );
  }

  bool stable(String value) =>
      validValue(value) &&
      selected(
        value,
      ).every((v) => !['unknown', 'variable', 'other'].contains(v));
  String labelFor(String value) =>
      values[value] ??
      values.entries
          .where((e) => selected(value).contains(e.key))
          .map((e) => e.value)
          .join(' / ');
  String encode(Iterable<String> selection) {
    final parts = selection.toSet().toList()..sort();
    return parts.isEmpty ? 'unknown' : parts.join('|');
  }

  bool matchesSelection(String recorded, String selection) =>
      selected(recorded).any(selected(selection).contains);
}

class ReviewProposal {
  const ReviewProposal(
    this.value,
    this.quote,
    this.explanation, {
    this.status = 'not_documented',
    this.hits = const [],
  });
  final String value, quote, explanation;
  final String status;
  final List<DictionaryHit> hits;
  bool get isCandidate => status == 'candidate';
}

class PhysciaPilot {
  static const genus = 'Physcia';
  static const presence = {
    'present': 'Presente',
    'absent': 'Assente',
    'variable': 'Variabile / condizionato',
    'unknown': 'Non documentato / incerto',
  };
  static const typeQualifiers = {
    'other': 'Altro · non usato nella chiave',
    'variable': 'Variabile / più tipi',
    'unknown': 'Non documentato / incerto',
  };
  static const characters = [
    PilotCharacter(
      'soredia',
      'Soredi',
      presence,
      'I sorali producono soredi: sorali presenti documentano soredi presenti. Puoi registrare manualmente Assente senza una citazione; la mancanza di una parola non genera assenze automatiche.',
    ),
    PilotCharacter(
      'isidia',
      'Isidi veri',
      presence,
      'Le strutture isidia-like, pustule e blastidi non equivalgono automaticamente a veri isidi.',
    ),
    PilotCharacter(
      'cilia',
      'Ciglia',
      presence,
      'Controlla la struttura e la porzione del tallo. L’assenza marginale non va generalizzata senza contesto.',
    ),
    PilotCharacter(
      'rhizines',
      'Rizine',
      presence,
      'Conserva le condizioni: rizine sparse alla base e altre zone erhizinate non descrivono un’assenza universale.',
    ),
    PilotCharacter(
      'apothecia_type',
      'Apoteci · tipo',
      {
        'lecideine': 'Lecideini',
        'lecanorine': 'Lecanorini',
        'biatorine': 'Biatorini',
        'absent': 'Assenti',
        'variable': 'Variabile / più tipi',
        'other': 'Altro tipo · non usato nella chiave',
        'unknown': 'Non documentato / incerto',
      },
      'Scegli il tipo di apoteci documentato. Se non sono presenti puoi salvare Assenti senza citazione o motivazione obbligatoria. La rarità degli apoteci non equivale alla loro assenza.',
    ),
    PilotCharacter(
      'soralia_shape',
      'Forma dei sorali',
      {
        'hood': 'A cappuccio',
        'labriform': 'Labriformi',
        'capitate': 'Capitati',
        'punctiform': 'Puntiformi',
        'linear': 'Lineari',
        'crateriform': 'Crateriformi',
        'orbicular': 'Orbicolari',
        'other': 'Altra forma · non usata nella chiave',
        'variable': 'Variabile / condizionata',
        'unknown': 'Non documentata / incerta',
      },
      'Confronta la forma dei sorali, non la granulosità dei soredi. Se il testo descrive cambiamenti o forme alternative conserva la variabilità.',
    ),
    PilotCharacter(
      'soralia_position',
      'Posizione dei sorali',
      {
        'terminal': 'Terminali / apicali',
        'marginal': 'Marginali',
        'laminal': 'Laminali',
        'other': 'Altra posizione · non usata nella chiave',
        'variable': 'Variabile / più posizioni',
        'unknown': 'Non documentata / incerta',
      },
      'Distingui la posizione dei sorali da quella di ciglia, rizine o lobi. Più posizioni o cambiamenti con l’età restano variabili.',
    ),
    PilotCharacter(
      'soredia_texture',
      'Consistenza dei soredi',
      {'farinose': 'Farinosi', 'granular': 'Granulari', ...typeQualifiers},
      'Descrivi la consistenza dei soredi, separatamente dalla forma dei sorali. Non applicabile se i soredi sono assenti.',
    ),
    PilotCharacter(
      'isidia_shape',
      'Forma degli isidi',
      {
        'cylindrical': 'Cilindrici',
        'coralloid': 'Coralloidi',
        'globose': 'Globosi',
        'flattened': 'Appiattiti',
        'branched': 'Ramificati',
        ...typeQualifiers,
      },
      'Associa la forma a isidi veri, distinguendoli da strutture simili. Non applicabile se gli isidi sono assenti.',
    ),
    PilotCharacter(
      'cilia_type',
      'Tipo di ciglia',
      {
        'simple': 'Semplici',
        'branched': 'Ramificate',
        'forked': 'Biforcate',
        'bulbate': 'Con base bulbosa',
        ...typeQualifiers,
      },
      'Il tipo deve riferirsi alle ciglia, non alle rizine o ad altre strutture. Non applicabile se le ciglia sono assenti.',
    ),
    PilotCharacter(
      'rhizines_type',
      'Tipo di rizine',
      {
        'simple': 'Semplici',
        'branched': 'Ramificate',
        'dichotomous': 'Dicotomiche',
        'squarrose': 'Squarrose',
        'tufted': 'A ciuffo',
        ...typeQualifiers,
      },
      'Conserva eventuali combinazioni o condizioni: più tipi non generano una proposta univoca. Non applicabile se le rizine sono assenti.',
    ),
    PilotCharacter(
      'apothecia_shape',
      'Forma degli apoteci',
      {
        'rounded': 'Arrotondati',
        'elongate': 'Allungati',
        'lirelliform': 'Lirelliformi',
        'irregular': 'Irregolari',
        ...typeQualifiers,
      },
      'La forma deve riferirsi agli apoteci, non alle cellule o al tallo. Non applicabile se gli apoteci sono registrati come assenti.',
    ),
    PilotCharacter(
      "thallus_type",
      "Tipo di tallo",
      {
        "foliose": "Foglioso",
        "subfruticose": "Subfruticoso",
        "fruticose": "Fruticoso",
        "crustose": "Crostoso",
        "squamulose": "Squamuloso",
        "leprose": "Leproso",
        ...typeQualifiers,
      },
      "Forma descritta nel testo, distinta dal codice generale ITALIC. Puoi conservare più forme, per esempio foglioso e subfruticoso.",
      multiple: true,
    ),
    PilotCharacter(
      "upper_surface_colour",
      "Colore superficie superiore",
      {
        "white": "Bianco / biancastro",
        "grey": "Grigio",
        "whitish_grey": "Grigio biancastro",
        "bluish_grey": "Grigio azzurrato",
        "lead_grey": "Grigio piombo",
        "brownish_grey": "Grigio brunastro",
        "greenish_grey": "Grigio verdastro",
        "greenish_white": "Bianco verdastro",
        "cream": "Crema",
        "brown": "Bruno / brunastro",
        "black": "Nero",
        "green": "Verde",
        "yellow": "Giallo",
        "orange": "Arancione",
        ...typeQualifiers,
      },
      "Colori della superficie superiore o dei lobi. Esclude il colore di macule, pruina, sorali, ciglia e apoteci. Conserva sfumature e localizzazioni nella citazione.",
      multiple: true,
    ),
    PilotCharacter(
      "lower_surface_colour",
      "Colore superficie inferiore",
      {
        "white": "Bianco / biancastro",
        "grey": "Grigio",
        "whitish_grey": "Grigio biancastro",
        "bluish_grey": "Grigio azzurrato",
        "lead_grey": "Grigio piombo",
        "brownish_grey": "Grigio brunastro",
        "greenish_grey": "Grigio verdastro",
        "greenish_white": "Bianco verdastro",
        "cream": "Crema",
        "brown": "Bruno / brunastro",
        "black": "Nero",
        "green": "Verde",
        "yellow": "Giallo",
        "orange": "Arancione",
        ...typeQualifiers,
      },
      "Colori della superficie inferiore, separati dal colore delle rizine. La citazione conserva eventuali differenze tra base, centro e apici.",
      multiple: true,
    ),
    PilotCharacter(
      "medulla_colour",
      "Colore della medulla",
      {
        "white": "Bianco / biancastro",
        "grey": "Grigio",
        "whitish_grey": "Grigio biancastro",
        "bluish_grey": "Grigio azzurrato",
        "lead_grey": "Grigio piombo",
        "brownish_grey": "Grigio brunastro",
        "greenish_grey": "Grigio verdastro",
        "greenish_white": "Bianco verdastro",
        "cream": "Crema",
        "brown": "Bruno / brunastro",
        "black": "Nero",
        "green": "Verde",
        "yellow": "Giallo",
        "orange": "Arancione",
        ...typeQualifiers,
      },
      "Colore della medulla nella descrizione anatomica. Le reazioni ai reagenti e la chimica non sono colori della medulla non trattata.",
      multiple: true,
    ),
    PilotCharacter(
      "lobe_width_class",
      "Lobi · larghezza descritta",
      {"narrow": "Stretti", "broad": "Larghi", ...typeQualifiers},
      "Classe esplicitamente descritta come narrow-lobed o broad-lobed. Non deduce una classe dalle misure in millimetri.",
      multiple: true,
    ),
    PilotCharacter(
      "lobe_shape",
      "Lobi · forma",
      {
        "strap_shaped": "Nastri / strap-shaped",
        "linear": "Lineari",
        "rounded": "Arrotondati",
        "truncate": "Troncati",
        ...typeQualifiers,
      },
      "Forma dei lobi. Non trasferisce ai lobi forme di cellule, spore, sorali o isidi.",
      multiple: true,
    ),
    PilotCharacter(
      "lobe_profile",
      "Lobi · profilo",
      {
        "flat": "Piatti",
        "convex": "Convessi",
        "concave": "Concavi",
        "canaliculate": "Canalicolati",
        ...typeQualifiers,
      },
      "Profilo dei lobi: per esempio flat to slightly convex conserva piatti e convessi, con la frase completa.",
      multiple: true,
    ),
    PilotCharacter(
      "lobe_posture",
      "Lobi · portamento",
      {
        "ascending": "Ascendenti",
        "erect": "Eretti",
        "adpressed": "Appressati",
        "spreading": "Distesi / divaricati",
        ...typeQualifiers,
      },
      "Portamento dei lobi nel tallo. Le condizioni e le variazioni rimangono nella citazione.",
      multiple: true,
    ),
    PilotCharacter(
      "thallus_attachment",
      "Adesione del tallo",
      {
        "loose": "Lassamente aderente",
        "close": "Strettamente appressato",
        "firm": "Saldamente aderente",
        ...typeQualifiers,
      },
      "Grado di adesione descritto per il tallo; distinto dalla forma e dalla larghezza dei lobi.",
      multiple: true,
    ),
    PilotCharacter(
      "thallus_outline",
      "Tallo · contorno",
      {
        "orbicular": "Orbicolare / a rosetta",
        "irregular": "Chiazze irregolari",
        ...typeQualifiers,
      },
      "Contorno delle colonie descritto nel testo. Più contorni possono essere documentati; non estende al tallo l’irregolarità di altre strutture.",
      multiple: true,
    ),
    PilotCharacter(
      "upper_surface_pruina",
      "Superficie superiore · pruina",
      {
        "present": "Presente",
        "absent": "Assente (epruinose)",
        ...typeQualifiers,
      },
      "Pruina della superficie superiore o dei lobi. La pruina del disco degli apoteci non documenta quella del tallo. La mancata menzione non significa assenza.",
      multiple: false,
    ),
    PilotCharacter(
      "upper_surface_maculation",
      "Superficie superiore · macule",
      {
        "present": "Presenti (maculate)",
        "absent": "Assenti (emaculate)",
        ...typeQualifiers,
      },
      "Macule della superficie superiore o dei lobi. Emaculate documenta l’assenza; il bianco delle macule non diventa automaticamente il colore del tallo.",
      multiple: false,
    ),
    PilotCharacter(
      "soralia",
      "Sorali · presenza",
      presence,
      "Presenza dei sorali distinta da quella dei soredi. Sorali presenti documentano soredi; soredi senza sorali non dimostrano sorali presenti.",
      multiple: false,
    ),
    PilotCharacter(
      "apothecia_insertion",
      "Apoteci · inserzione",
      {
        "sessile": "Sessili",
        "short_stipitate": "Brevemente peduncolati",
        "stipitate": "Peduncolati",
        "immersed": "Immersi",
        "adnate": "Adnati",
        ...typeQualifiers,
      },
      "Inserzione degli apoteci distinta dalla forma del contorno: short-stipitate indica un breve peduncolo. Conserva rarità e condizioni nella citazione.",
      multiple: true,
    ),
    PilotCharacter(
      "apothecia_disc_pruina",
      "Apoteci · pruina del disco",
      {
        "present": "Presente",
        "absent": "Assente (epruinose)",
        ...typeQualifiers,
      },
      "Pruina del disco degli apoteci, distinta dalla pruina del tallo e del margine. Sometimes pruinose resta condizionato e da chiarire.",
      multiple: false,
    ),
  ];
  static bool inScope(ItalicTaxon taxon) =>
      taxon.scientificName.split(' ').first == genus;
  static PilotCharacter? character(String id) {
    for (final c in characters) {
      if (c.id == id) return c;
    }
    return null;
  }

  static const dependencies = {
    'soralia_shape': 'soredia',
    'soralia_position': 'soredia',
    'soredia_texture': 'soredia',
    'isidia_shape': 'isidia',
    'cilia_type': 'cilia',
    'rhizines_type': 'rhizines',
    'apothecia_shape': 'apothecia_type',
    'soralia': 'soredia',
    'apothecia_insertion': 'apothecia_type',
    'apothecia_disc_pruina': 'apothecia_type',
  };
  static bool dependsOnSoredia(String id) => dependencies[id] == 'soredia';
  static Iterable<String> parents(String id) sync* {
    if (dependencies[id] case final parent?) yield parent;
    if (id == 'soralia_shape' || id == 'soralia_position') yield 'soralia';
  }

  static String? absentSampleParent(String id, Map<String, String> selections) {
    for (final parent in parents(id)) {
      if (selections[parent] == 'absent') return parent;
    }
    return null;
  }

  static CharacterReview? _absence(
    ReviewRegistry registry,
    ItalicTaxon taxon,
    String parent,
  ) {
    final record = registry.latest(taxon.italicId!, parent);
    return record != null &&
            record.value == 'absent' &&
            record.reviewer.trim().isNotEmpty &&
            record.matches(taxon)
        ? record
        : null;
  }

  static CharacterReview? sorediaAbsence(
    ReviewRegistry registry,
    ItalicTaxon taxon,
  ) => _absence(registry, taxon, 'soredia');

  static CharacterReview? absenceFor(
    ReviewRegistry registry,
    ItalicTaxon taxon,
    String characterId,
  ) {
    for (final parent in parents(characterId)) {
      final absence = _absence(registry, taxon, parent);
      if (absence != null) return absence;
    }
    return null;
  }

  static String absenceLabel(CharacterReview absence) =>
      '${character(absence.characterId)!.label}: Assente';

  static ReviewProposal proposal(
    MatrixTaxon row,
    PilotCharacter character, {
    required CharacterDictionary dictionary,
  }) {
    final concept = dictionary.characters.singleWhere(
      (c) => c.id == character.id,
    );
    final analysis = dictionary.analyze(row.taxon.description ?? '', concept);
    final candidate =
        analysis.isCandidate && character.validValue(analysis.value);
    return ReviewProposal(
      candidate ? analysis.value! : 'unknown',
      analysis.hits.isEmpty
          ? ''
          : candidate && analysis.values.length > 1
          ? row.taxon.description!.substring(
              analysis.hits.map((h) => h.start).reduce((a, b) => a < b ? a : b),
              analysis.hits.map((h) => h.end).reduce((a, b) => a > b ? a : b),
            )
          : analysis.hits.first.quote,
      candidate
          ? 'Proposta del dizionario da una frase esatta, da revisionare.${character.id == 'soredia' ? ' I sorali documentano la presenza di soredi.' : ''} Verifica sempre il contesto.'
          : analysis.hits.isEmpty
          ? 'Il dizionario non trova evidenze per questo carattere. Non documentato non significa assente.'
          : 'Il dizionario trova menzioni con condizioni, confronti, negazioni o più stati. Il valore resta incerto: controlla le frasi prima di scegliere.',
      status: candidate
          ? 'candidate'
          : analysis.status == 'not_documented'
          ? 'not_documented'
          : 'needs_review',
      hits: analysis.hits,
    );
  }

  static void validate(CharacterReview review, ItalicTaxon taxon) {
    final definition = character(review.characterId);
    if (!inScope(taxon) ||
        definition == null ||
        !definition.validValue(review.value) ||
        !['draft', 'reviewed', 'clarify'].contains(review.status) ||
        review.reviewer.trim().isEmpty ||
        review.id.isEmpty ||
        review.version < 1 ||
        !review.matches(taxon)) {
      throw const FormatException(
        'Revisione non valida: controlla autore, valore, citazione e fonte.',
      );
    }
    if (review.quote.isNotEmpty &&
        !(taxon.description ?? '').contains(review.quote)) {
      throw const FormatException(
        'La citazione deve essere presente esattamente nella descrizione.',
      );
    }
    if (['variable', 'other'].contains(review.value) &&
        review.notes.trim().isEmpty) {
      throw const FormatException(
        'Descrivi nelle note la variabilità o l’altro stato.',
      );
    }
  }

  static bool usable(
    CharacterReview? review,
    ItalicTaxon taxon,
    PilotCharacter character,
  ) =>
      review != null &&
      review.characterId == character.id &&
      review.isReviewed &&
      character.stable(review.value) &&
      review.reviewer.trim().isNotEmpty &&
      review.matches(taxon);
}

class ReviewedCriterion {
  const ReviewedCriterion(
    this.character,
    this.selection,
    this.review,
    this.matches, {
    this.notApplicable = false,
  });
  final PilotCharacter character;
  final String selection;
  final CharacterReview? review;
  final bool? matches;
  final bool notApplicable;
}

class ReviewedCandidate {
  const ReviewedCandidate(this.row, this.criteria);
  final MatrixTaxon row;
  final List<ReviewedCriterion> criteria;
  bool get different => criteria.any((c) => c.matches == false);
  bool get uncertain =>
      criteria.isEmpty || criteria.any((c) => c.matches == null);
}

class ReviewedResult {
  const ReviewedResult(this.matching, this.uncertain, this.different);
  final List<ReviewedCandidate> matching, uncertain, different;
}

class PhysciaReviewEngine {
  ReviewedResult evaluate(
    CharacterMatrix matrix,
    ReviewRegistry registry,
    Map<String, String> selections,
  ) {
    final matching = <ReviewedCandidate>[],
        uncertain = <ReviewedCandidate>[],
        different = <ReviewedCandidate>[];
    for (final row in matrix.taxa.where((r) => PhysciaPilot.inScope(r.taxon))) {
      final criteria = <ReviewedCriterion>[];
      for (final c in PhysciaPilot.characters) {
        if (PhysciaPilot.absentSampleParent(c.id, selections) != null) {
          continue;
        }
        final choice = selections[c.id];
        if (choice == null || !c.stable(choice)) continue;
        final absence = PhysciaPilot.absenceFor(registry, row.taxon, c.id);
        if (absence != null) {
          criteria.add(
            ReviewedCriterion(
              c,
              choice,
              absence,
              absence.isReviewed ? false : null,
              notApplicable: true,
            ),
          );
          continue;
        }
        final review = registry.latest(row.taxon.italicId!, c.id);
        final agrees = !PhysciaPilot.usable(review, row.taxon, c)
            ? null
            : c.matchesSelection(review!.value, choice);
        criteria.add(ReviewedCriterion(c, choice, review, agrees));
      }
      final candidate = ReviewedCandidate(row, criteria);
      if (candidate.different) {
        different.add(candidate);
      } else if (candidate.uncertain) {
        uncertain.add(candidate);
      } else {
        matching.add(candidate);
      }
    }
    return ReviewedResult(matching, uncertain, different);
  }
}
