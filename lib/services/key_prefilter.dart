import '../data/character_matrix_repository.dart';
import '../data/italic_api_traits_repository.dart';
import 'reconstructed_key.dart';
import 'structured_key_engine.dart';
import 'thallus_colour.dart';

/// Optional comparisons with documented structured and binary traits.
/// Unknown or stale evidence never excludes a taxon.
class KeyPrefilter {
  static final legacyQuestions = StructuredKey.questions
      .where((q) => q.id != 'reproductiveStrategy')
      .toList();
  static const binaryCharacters = [
    ApiTraitCharacter("growth_form_fruticose", "Tallo fruticoso"),
    ApiTraitCharacter("growth_form_foliose", "Tallo foglioso"),
    ApiTraitCharacter("growth_form_squamulose", "Tallo squamuloso"),
    ApiTraitCharacter("growth_form_leprose", "Tallo leproso"),
    ApiTraitCharacter("growth_form_crustose", "Tallo crostoso"),
    ApiTraitCharacter("growth_form_lichenicolous", "Lichenicolo"),
    ApiTraitCharacter("photobiont_cyanobacterial", "Fotobionte cianobatterico"),
    ApiTraitCharacter(
      "photobiont_trentepohlioid",
      "Fotobionte trentepohlioide",
    ),
    ApiTraitCharacter("photobiont_chlorococcoid", "Fotobionte clorococcoide"),
    ApiTraitCharacter("photobiont_absent", "Fotobionte assente"),
    ApiTraitCharacter("ascocarps_present", "Ascocarpi presenti"),
    ApiTraitCharacter("ascocarps_perithecioid", "Ascocarpi peritecioidi"),
    ApiTraitCharacter("ascocarps_apothecioid", "Ascocarpi apotecioidi"),
    ApiTraitCharacter("apothecia_lecanorine", "Apoteci lecanorini"),
    ApiTraitCharacter("apothecia_lirelliform", "Apoteci lirelliformi"),
    ApiTraitCharacter("ascospores_pigmented", "Ascospore pigmentate"),
    ApiTraitCharacter("ascospores_hyaline", "Ascospore ialine"),
    ApiTraitCharacter("ascospores_1-celled", "Ascospore unicellulari"),
    ApiTraitCharacter("ascospores_2-celled", "Ascospore bicellulari"),
    ApiTraitCharacter(
      "ascospores_more_than_2-celled",
      "Ascospore con più di due cellule",
    ),
    ApiTraitCharacter("ascospores_polarilocular", "Ascospore polariloculari"),
    ApiTraitCharacter(
      "ascospores_muriform_or_submuriform",
      "Ascospore muriformi / submuriformi",
    ),
    ApiTraitCharacter(
      "ascospores_less_than_8_per_ascus",
      "Meno di 8 ascospore per asco",
    ),
    ApiTraitCharacter("ascospores_8_per_ascus", "8 ascospore per asco"),
    ApiTraitCharacter(
      "ascospores_more_than_8_per_ascus",
      "Più di 8 ascospore per asco",
    ),
    ApiTraitCharacter("cortex_k_negative", "Corteccia K−"),
    ApiTraitCharacter(
      "cortex_k_yellow_to_orange",
      "Corteccia K+ giallo / arancio",
    ),
    ApiTraitCharacter("cortex_k_red", "Corteccia K+ rosso"),
    ApiTraitCharacter(
      "cortex_k_yellow_turning_to_red",
      "Corteccia K+ giallo → rosso",
    ),
    ApiTraitCharacter(
      "reproduction_soredia_or_similar",
      "Riproduzione · soredi o strutture simili",
    ),
    ApiTraitCharacter(
      "reproduction_isidia_or_similar",
      "Riproduzione · isidi o strutture simili",
    ),
  ];
  static final binaryQuestions = [
    for (final c in binaryCharacters)
      StructuredQuestion(
        'binary:${c.id}',
        c.label,
        c.label,
        'Matrice binaria ITALIC. Non so mantiene i candidati.',
        const [
          StructuredChoice('1', 'Sì / presente', {'1'}),
          StructuredChoice('0', 'No / assente', {'0'}),
        ],
      ),
  ];
  static final questions = [
    ...legacyQuestions,
    ThallusColour.question,
    ...binaryQuestions,
  ];
  static Map<String, String> normalize(Map<String, String> input) => {
    for (final q in questions)
      if (q.choice(input[q.id] ?? '') != null) q.id: input[q.id]!,
  };
  static Map<String, String> restore(Map<String, String> selections) =>
      normalize({
        for (final q in questions) q.id: selections['_trait:${q.id}'] ?? '',
      });
  static String summary(Map<String, String> input) => questions
      .where((q) => normalize(input).containsKey(q.id))
      .map((q) => '${q.title}: ${q.label(input[q.id]!)}')
      .join(' · ');

  KeyPrefilter(
    ReconstructedKey key,
    CharacterMatrix matrix,
    Map<String, String> input, {
    ApiTraitsMatrix? apiMatrix,
  }) {
    filters = normalize(input);
    final rows = {for (final r in matrix.taxa) r.taxon.italicId: r};
    final selections = {
      for (final q in StructuredKey.questions)
        q.id: filters[q.id] ?? StructuredKey.unknown,
    };
    final engine = StructuredKey();
    final apiRows = {
      for (final r in apiMatrix?.taxa ?? <ApiTraitRow>[]) r.taxon.italicId: r,
    };
    for (final t in {...key.taxa, ...key.unrepresented}.values) {
      final row = rows[t.italicId];
      final assessment =
          row == null || row.taxon.scientificName != t.scientificName
          ? null
          : engine.assess(row, selections);
      var differs = assessment?.differs == true;
      var missing =
          filters.keys.any((id) => legacyQuestions.any((q) => q.id == id)) &&
          (assessment == null || assessment.uncertain);
      final colour = filters[ThallusColour.id];
      if (colour != null) {
        final agrees =
            row == null || row.taxon.scientificName != t.scientificName
            ? null
            : ThallusColour.matches(row, colour);
        if (agrees == null) missing = true;
        if (agrees == false) differs = true;
      }
      final api = apiRows[t.italicId];
      for (final entry in filters.entries.where(
        (e) => e.key.startsWith('binary:'),
      )) {
        final id = entry.key.substring(7);
        final unreliable =
            api == null ||
            api.taxon.scientificName != t.scientificName ||
            api.warning.isNotEmpty ||
            api.schemaIssueCount > 0 ||
            api.descriptionChanged ||
            api.conflicts.any((c) => c.concerns(id)) ||
            (id.startsWith('reproduction_') && api.reproductionChanged);
        final value = unreliable ? null : api.values[id];
        if (value == null) {
          missing = true;
        } else if (value.toString() != entry.value) {
          differs = true;
        }
      }
      if (differs) {
        excluded.add(t.italicId!);
      } else {
        eligible.add(t.italicId!);
        if (filters.isNotEmpty && missing) {
          uncertain.add(t.italicId!);
        }
      }
    }
    coveredLocal = key.taxa.keys
        .where((id) => !key.extraTaxa.contains(id) && eligible.contains(id))
        .length;
  }
  late final Map<String, String> filters;
  final eligible = <int>{}, uncertain = <int>{}, excluded = <int>{};
  late final int coveredLocal;
}
