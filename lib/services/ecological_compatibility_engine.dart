import '../data/italic_reference_repository.dart';

/// Valutazione descrittiva, NON probabilità di identificazione.
enum EvidenceStatus { compatible, incompatible, unknown, notDocumented, reportedAbsent }

class EcologicalCriterion {
  const EcologicalCriterion(this.label, this.status, this.explanation);
  final String label;
  final EvidenceStatus status;
  final String explanation;
}

class EcologicalAssessment {
  const EcologicalAssessment(this.criteria);
  final List<EcologicalCriterion> criteria;

  int get evaluated => criteria.where((c) => c.status == EvidenceStatus.compatible || c.status == EvidenceStatus.incompatible).length;
  int get compatible => criteria.where((c) => c.status == EvidenceStatus.compatible).length;
  int get requested => criteria.length;
  int get unknown => criteria.where((c) => c.status == EvidenceStatus.unknown).length;
  int get notDocumented => criteria.where((c) => c.status == EvidenceStatus.notDocumented).length;
  int get reportedAbsent => criteria.where((c) => c.status == EvidenceStatus.reportedAbsent).length;
  int get incompatible => criteria.where((c) => c.status == EvidenceStatus.incompatible).length;
  /// Null se non è possibile valutare alcun criterio.
  int? get score => evaluated == 0 ? null : (100 * compatible / evaluated).round();
  double get coverage => requested == 0 ? 0 : evaluated / requested;
}

class EcologicalQuery {
  const EcologicalQuery({
    this.region = 'Tutte', this.belt = 'Tutte',
    this.substrate = 'Tutti', this.growthForm = 'Tutte',
  });
  final String region, belt, substrate, growthForm;
}

class EcologicalCompatibilityEngine {
  static const regionCodes = <String, String>{
    'Abruzzo':'Abr', 'Basilicata':'Bas', 'Calabria':'Cal',
    'Campania':'Camp', 'Emilia-Romagna':'Emil',
    'Friuli-Venezia Giulia':'Frl', 'Lazio':'Laz', 'Liguria':'Lig',
    'Lombardia':'Lomb', 'Marche':'Marc', 'Molise':'Mol',
    'Piemonte':'Piem', 'Puglia':'Pugl', 'Sardegna':'Sar',
    'Sicilia':'Si', 'Toscana':'Tosc', 'Trentino-Alto Adige':'TAA',
    'Umbria':'Umb', "Valle d'Aosta":'VA', 'Veneto':'Ven',
  };

  static String cleanEcology(String? raw) => (raw ?? '')
      .split(RegExp(r'\s+Photobiont\s*:', caseSensitive: false))
      .first.trim().toLowerCase();

  static String geographyWithoutCitations(String input) {
    final output = StringBuffer();
    var depth = 0;
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      if (ch == '(') { depth++; }
      else if (ch == ')') { if (depth > 0) depth--; }
      else if (depth == 0) { output.write(ch); }
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
    return codes.any((c) => RegExp(
      r'(^|[^A-Za-z])' + RegExp.escape(c) + r'(?=[^A-Za-z]|$)',
      caseSensitive: false,
    ).hasMatch(geography));
  }

  static bool? beltMatch(ItalicTaxon taxon, String belt) {
    final raw = taxon.belts[belt]?.toString().trim().toLowerCase();
    if (raw == null || raw.isEmpty) return null;
    return raw != 'absent';
  }

  static bool? substrateMatch(ItalicTaxon taxon, String substrate) {
    final value = cleanEcology(taxon.substrata);
    if (value.isEmpty) return null;
    switch (substrate) {
      case 'Roccia': return RegExp(r'\brocks?\b').hasMatch(value);
      case 'Corteccia': return RegExp(r'\bbark\b').hasMatch(value);
      case 'Legno': return RegExp(r'\blignum\b').hasMatch(value);
      case 'Suolo, muschi e detriti':
        return RegExp(r'\bsoil\b|\bterricolous mosses\b|\bplant debris\b').hasMatch(value);
      case 'Foglie': return RegExp(r'\bleaves\b').hasMatch(value);
      default: return null;
    }
  }

  static bool? growthMatch(ItalicTaxon taxon, String growthForm) {
    final value = cleanEcology(taxon.growthForm);
    if (value.isEmpty) return null;
    switch (growthForm) {
      case 'Crostoso': return value.startsWith('crustose');
      case 'Foglioso': return value.startsWith('foliose');
      case 'Fruticoso': return value.startsWith('fruticose');
      case 'Squamuloso': return value.startsWith('squamulose');
      case 'Leproso': return value.startsWith('leprose');
      case 'Fungo lichenicolo': return value.startsWith('lichenicolous fungus');
      case 'Non lichenizzato': return value.startsWith('non-lichenised');
      default: return null;
    }
  }

  static EcologicalCriterion criterion(String label, bool? match, String detail) =>
      EcologicalCriterion(label,
        match == null ? EvidenceStatus.unknown :
        match ? EvidenceStatus.compatible : EvidenceStatus.incompatible,
        match == null ? '$detail: dato non disponibile' :
        match ? '$detail: compatibile' : '$detail: non compatibile secondo i dati disponibili');

  EcologicalCriterion regionCriterion(ItalicTaxon taxon, String region) {
    final raw = taxon.distribution;
    final code = regionCodes[region];
    if (code == null || raw == null || raw.trim().isEmpty ||
        geographyWithoutCitations(raw).trim().isEmpty) {
      return EcologicalCriterion('Regione', EvidenceStatus.unknown,
          '$region: distribuzione non disponibile');
    }
    if (regionMatch(taxon, region) == true) {
      return EcologicalCriterion('Regione', EvidenceStatus.compatible,
          '$region: presenza documentata nei dati ITALIC');
    }
    return EcologicalCriterion('Regione', EvidenceStatus.notDocumented,
        '$region: presenza non documentata nei dati disponibili; non significa assenza');
  }

  EcologicalCriterion beltCriterion(ItalicTaxon taxon, String belt) {
    final raw = taxon.belts[belt]?.toString().trim();
    if (raw == null || raw.isEmpty) {
      return EcologicalCriterion('Fascia', EvidenceStatus.unknown,
          '$belt: informazione non disponibile');
    }
    if (raw.toLowerCase() == 'absent') {
      return EcologicalCriterion('Fascia', EvidenceStatus.reportedAbsent,
          '$belt: indicata come "absent" in ITALIC; non è prova di assenza assoluta');
    }
    return EcologicalCriterion('Fascia', EvidenceStatus.compatible,
        '$belt: indicazione ITALIC "$raw"');
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
      criteria.add(criterion('Substrato', substrateMatch(taxon, query.substrate), query.substrate));
    }
    if (query.growthForm != 'Tutte') {
      criteria.add(criterion('Forma', growthMatch(taxon, query.growthForm), query.growthForm));
    }
    return EcologicalAssessment(criteria);
  }
}
