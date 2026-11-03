import '../data/italic_reference_repository.dart';
import '../models/ecological_scale.dart';

/// Valutazione descrittiva, NON probabilità di identificazione.
enum EvidenceStatus {
  compatible,
  incompatible,
  unknown,
  notDocumented,
  reportedAbsent,
}

class EcologicalCriterion {
  const EcologicalCriterion(this.label, this.status, this.explanation);
  final String label;
  final EvidenceStatus status;
  final String explanation;
}

class EcologicalAssessment {
  const EcologicalAssessment(this.criteria);
  final List<EcologicalCriterion> criteria;

  int get evaluated => criteria
      .where(
        (c) =>
            c.status == EvidenceStatus.compatible ||
            c.status == EvidenceStatus.incompatible ||
            c.status == EvidenceStatus.reportedAbsent,
      )
      .length;
  int get compatible =>
      criteria.where((c) => c.status == EvidenceStatus.compatible).length;
  int get requested => criteria.length;
  int get unknown =>
      criteria.where((c) => c.status == EvidenceStatus.unknown).length;
  int get notDocumented =>
      criteria.where((c) => c.status == EvidenceStatus.notDocumented).length;
  int get reportedAbsent =>
      criteria.where((c) => c.status == EvidenceStatus.reportedAbsent).length;
  int get incompatible =>
      criteria.where((c) => c.status == EvidenceStatus.incompatible).length;

  /// Null se non è possibile valutare alcun criterio.
  int? get score =>
      evaluated == 0 ? null : (100 * compatible / evaluated).round();
  double get coverage => requested == 0 ? 0 : evaluated / requested;
}

class EcologicalQuery {
  const EcologicalQuery({
    this.region = 'Tutte',
    this.belt = 'Tutte',
    this.substrate = 'Tutti',
    this.growthForm = 'Tutte',
    this.photobiont = '',
    this.reproductiveStrategy = '',
    this.scales = const {},
  });
  final String region, belt, substrate, growthForm;
  final String photobiont, reproductiveStrategy;
  final Map<String, int> scales;
}

class EcologicalCompatibilityEngine {
  static const regionCodes = <String, String>{
    'Abruzzo': 'Abr',
    'Basilicata': 'Bas',
    'Calabria': 'Cal',
    'Campania': 'Camp',
    'Emilia-Romagna': 'Emil',
    'Friuli-Venezia Giulia': 'Frl',
    'Lazio': 'Laz',
    'Liguria': 'Lig',
    'Lombardia': 'Lomb',
    'Marche': 'Marc',
    'Molise': 'Mol',
    'Piemonte': 'Piem',
    'Puglia': 'Pugl',
    'Sardegna': 'Sar',
    'Sicilia': 'Si',
    'Toscana': 'Tosc',
    'Trentino-Alto Adige': 'TAA',
    'Umbria': 'Umb',
    "Valle d'Aosta": 'VA',
    'Veneto': 'Ven',
  };

  static String cleanEcology(String? raw) => (raw ?? '')
      .split(RegExp(r'\s+Photobiont\s*:', caseSensitive: false))
      .first
      .trim()
      .toLowerCase();

  static String geographyWithoutCitations(String input) {
    final output = StringBuffer();
    var depth = 0;
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      if (ch == '(') {
        depth++;
      } else if (ch == ')') {
        if (depth > 0) depth--;
      } else if (depth == 0) {
        output.write(ch);
      }
    }
    return output.toString();
  }

  static bool? regionMatch(ItalicTaxon taxon, String region) {
    final raw = taxon.distribution;
    if (raw == null || raw.trim().isEmpty) return null;
    final code = regionCodes[region];
    if (code == null) return null;
    final geography = geographyWithoutCitations(raw);
    final codes = region == 'Friuli-Venezia Giulia' ? [code, 'VG'] : [code];
    return codes.any(
      (c) => RegExp(
        r'(^|[^A-Za-z])' + RegExp.escape(c) + r'(?=[^A-Za-z]|$)',
        caseSensitive: false,
      ).hasMatch(geography),
    );
  }

  static bool? beltMatch(ItalicTaxon taxon, String belt) {
    final raw = taxon.belts[belt]?.toString().trim().toLowerCase();
    if (raw == null || raw.isEmpty) return null;
    return raw != 'absent';
  }

  static bool? substrateMatch(ItalicTaxon taxon, String substrate) {
    const codes = {
      'Roccia': 'Sax',
      'Corteccia': 'Epiph',
      'Legno': 'Lign',
      'Suolo, muschi e detriti': 'Terr',
      'Foglie': 'Foliic',
    };
    if (taxon.ecologyCodes.containsKey('substrata')) {
      final code = taxon.ecologyCodes['substrata']!;
      if (code.isEmpty || !codes.containsKey(substrate)) return null;
      return code.split('-').contains(codes[substrate]);
    }
    final value = cleanEcology(taxon.substrata);
    if (value.isEmpty) return null;
    switch (substrate) {
      case 'Roccia':
        return RegExp(r'\brocks?\b').hasMatch(value);
      case 'Corteccia':
        return RegExp(r'\bbark\b').hasMatch(value);
      case 'Legno':
        return RegExp(r'\blignum\b').hasMatch(value);
      case 'Suolo, muschi e detriti':
        return RegExp(
          r'\bsoil\b|\bterricolous mosses\b|\bplant debris\b',
        ).hasMatch(value);
      case 'Foglie':
        return RegExp(r'\bleaves\b').hasMatch(value);
      default:
        return null;
    }
  }

  static bool? growthMatch(ItalicTaxon taxon, String growthForm) {
    const codes = {
      'Crostoso': 'Cr',
      'Foglioso': 'Fol',
      'Fruticoso': 'Frut',
      'Squamuloso': 'Sq',
      'Leproso': 'Lepr',
      'Fungo lichenicolo': 'LF',
      'Non lichenizzato': 'F',
    };
    if (taxon.ecologyCodes.containsKey('growthForm')) {
      final code = taxon.ecologyCodes['growthForm']!;
      final expected = codes[growthForm];
      if (code.isEmpty || expected == null) return null;
      return code == expected || code.startsWith('$expected.');
    }
    final value = cleanEcology(taxon.growthForm);
    if (value.isEmpty) return null;
    switch (growthForm) {
      case 'Crostoso':
        return value.startsWith('crustose');
      case 'Foglioso':
        return value.startsWith('foliose');
      case 'Fruticoso':
        return value.startsWith('fruticose');
      case 'Squamuloso':
        return value.startsWith('squamulose');
      case 'Leproso':
        return value.startsWith('leprose');
      case 'Fungo lichenicolo':
        return value.startsWith('lichenicolous fungus');
      case 'Non lichenizzato':
        return value.startsWith('non-lichenised');
      default:
        return null;
    }
  }

  static EcologicalCriterion criterion(
    String label,
    bool? match,
    String detail,
  ) => EcologicalCriterion(
    label,
    match == null
        ? EvidenceStatus.unknown
        : match
        ? EvidenceStatus.compatible
        : EvidenceStatus.incompatible,
    match == null
        ? '$detail: dato non disponibile'
        : match
        ? '$detail: compatibile'
        : '$detail: non compatibile secondo i dati disponibili',
  );

  static const photobiontOptions = <String, String>{
    '': 'Tutti',
    'Ch': 'Alghe verdi diverse da Trentepohlia',
    'Tr': 'Trentepohlia',
    'Cy.h': 'Cianobatteri filamentosi',
    'Cy.c': 'Cianobatteri coccoidi',
  };
  static const reproductionOptions = <String, String>{
    '': 'Tutte',
    'S': 'Riproduzione sessuata',
    'A.s': 'Soredi o strutture simili',
    'A.i': 'Isidi o strutture simili',
    'A.f': 'Frammentazione del tallo',
    'A.c': 'Conidi e talloconidi',
  };

  static bool? photobiontMatch(ItalicTaxon taxon, String selection) {
    if (!photobiontOptions.containsKey(selection) || selection.isEmpty) {
      return null;
    }
    if (taxon.ecologyCodes.containsKey('photobiont')) {
      final codes = taxon.ecologyCodes['photobiont']!;
      return codes.isEmpty ? null : codes.split('-').contains(selection);
    }
    final text = cleanEcology(taxon.photobiont);
    if (text.isEmpty) return null;
    return switch (selection) {
      'Ch' => text.contains('green algae other than trentepohlia'),
      'Tr' => text == 'trentepohlia' || text.startsWith('trentepohlioid'),
      'Cy.h' => text.contains('filamentous') || text.contains('nostoc'),
      'Cy.c' => text.contains('coccaceous') || text.contains('gloeocapsa'),
      _ => null,
    };
  }

  static bool? reproductionMatch(ItalicTaxon taxon, String selection) {
    if (!reproductionOptions.containsKey(selection) || selection.isEmpty) {
      return null;
    }
    if (taxon.ecologyCodes.containsKey('reproductiveStrategy')) {
      final codes = taxon.ecologyCodes['reproductiveStrategy']!;
      return codes.isEmpty ? null : codes.split('-').contains(selection);
    }
    final text = cleanEcology(taxon.reproductiveStrategy);
    if (text.isEmpty) return null;
    return switch (selection) {
      'S' => text.contains('mainly sexual'),
      'A.s' => text.contains('asexual') && text.contains('soredia'),
      'A.i' => text.contains('asexual') && text.contains('isidia'),
      'A.f' => text.contains('asexual') && text.contains('fragmentation'),
      'A.c' => text.contains('asexual') && text.contains('conidia'),
      _ => null,
    };
  }

  EcologicalCriterion scaleCriterion(
    ItalicTaxon taxon,
    EcologicalScaleDefinition definition,
    int selection,
  ) {
    final range = definition.range(taxon.ecologicalScales[definition.key]);
    if (selection < definition.min ||
        selection > definition.max ||
        range == null) {
      return EcologicalCriterion(
        definition.label,
        EvidenceStatus.unknown,
        '${definition.label}: classe $selection; intervallo non disponibile o non valido',
      );
    }
    final matches = selection >= range.$1 && selection <= range.$2;
    final interval = range.$1 == range.$2
        ? '${range.$1}'
        : '${range.$1}–${range.$2}';
    return EcologicalCriterion(
      definition.label,
      matches ? EvidenceStatus.compatible : EvidenceStatus.incompatible,
      '${definition.label}: classe $selection ${matches ? "compresa" : "non compresa"} '
      'nell’intervallo ITALIC $interval',
    );
  }

  /// Shared by the catalogue and tests so ranking cannot diverge.
  static int compare(EcologicalAssessment a, EcologicalAssessment b) {
    final matches = b.compatible.compareTo(a.compatible);
    if (matches != 0) return matches;
    final contradictions = (a.incompatible + a.reportedAbsent).compareTo(
      b.incompatible + b.reportedAbsent,
    );
    if (contradictions != 0) return contradictions;
    return b.evaluated.compareTo(a.evaluated);
  }

  EcologicalCriterion regionCriterion(ItalicTaxon taxon, String region) {
    final raw = taxon.distribution;
    final code = regionCodes[region];
    if (code == null ||
        raw == null ||
        raw.trim().isEmpty ||
        geographyWithoutCitations(raw).trim().isEmpty) {
      return EcologicalCriterion(
        'Regione',
        EvidenceStatus.unknown,
        '$region: distribuzione non disponibile',
      );
    }
    if (regionMatch(taxon, region) == true) {
      return EcologicalCriterion(
        'Regione',
        EvidenceStatus.compatible,
        '$region: presenza documentata nei dati ITALIC',
      );
    }
    return EcologicalCriterion(
      'Regione',
      EvidenceStatus.notDocumented,
      '$region: presenza non documentata nei dati disponibili; non significa assenza',
    );
  }

  EcologicalCriterion beltCriterion(ItalicTaxon taxon, String belt) {
    final raw = taxon.belts[belt]?.toString().trim();
    if (raw == null || raw.isEmpty) {
      return EcologicalCriterion(
        'Fascia',
        EvidenceStatus.unknown,
        '$belt: informazione non disponibile',
      );
    }
    if (raw.toLowerCase() == 'absent') {
      return EcologicalCriterion(
        'Fascia',
        EvidenceStatus.reportedAbsent,
        '$belt: indicata come "absent" in ITALIC; non è prova di assenza assoluta',
      );
    }
    return EcologicalCriterion(
      'Fascia',
      EvidenceStatus.compatible,
      '$belt: indicazione ITALIC "$raw"',
    );
  }

  EcologicalAssessment evaluate(ItalicTaxon taxon, EcologicalQuery query) {
    final criteria = <EcologicalCriterion>[];
    if (query.region != 'Tutte') {
      criteria.add(regionCriterion(taxon, query.region));
    }
    if (query.belt != 'Tutte') {
      criteria.add(beltCriterion(taxon, query.belt));
    }
    if (query.substrate != 'Tutti') {
      criteria.add(
        criterion(
          'Substrato',
          substrateMatch(taxon, query.substrate),
          query.substrate,
        ),
      );
    }
    if (query.growthForm != 'Tutte') {
      criteria.add(
        criterion(
          'Forma',
          growthMatch(taxon, query.growthForm),
          query.growthForm,
        ),
      );
    }
    if (query.photobiont.isNotEmpty) {
      criteria.add(
        criterion(
          'Fotobionte',
          photobiontMatch(taxon, query.photobiont),
          photobiontOptions[query.photobiont] ?? query.photobiont,
        ),
      );
    }
    if (query.reproductiveStrategy.isNotEmpty) {
      criteria.add(
        criterion(
          'Riproduzione',
          reproductionMatch(taxon, query.reproductiveStrategy),
          reproductionOptions[query.reproductiveStrategy] ??
              query.reproductiveStrategy,
        ),
      );
    }
    for (final definition in EcologicalScaleDefinition.all) {
      final selection = query.scales[definition.key];
      if (selection != null) {
        criteria.add(scaleCriterion(taxon, definition, selection));
      }
    }
    return EcologicalAssessment(criteria);
  }
}
