import '../data/italic_reference_repository.dart';
import '../models/observation.dart';

class FieldAchievement {
  const FieldAchievement(this.target, this.title, this.description);
  final int target;
  final String title, description;
}

const fieldAchievements = [
  FieldAchievement(1, 'Primo incontro', 'La prima specie del tuo diario.'),
  FieldAchievement(
    5,
    'Occhio curioso',
    'Cinque specie, cinque nuove scoperte.',
  ),
  FieldAchievement(10, 'Esploratore', 'Il tuo mondo di licheni si allarga.'),
  FieldAchievement(
    25,
    'Passo da naturalista',
    'Un diario sempre più ricco di diversità.',
  ),
  FieldAchievement(
    50,
    'Sguardo allenato',
    'Cinquanta specie incontrate sul campo.',
  ),
  FieldAchievement(
    100,
    'Cento scoperte',
    'Cento specie diverse nel tuo diario.',
  ),
];

/// Names resolve against the local checklist. Synonyms and infraspecific taxa
/// share the accepted species' binomial, so another photo or variety is not a
/// second species. Ambiguous aliases and unfinished identifications do not count.
class FieldAchievementIndex {
  FieldAchievementIndex(Iterable<ItalicTaxon> taxa) {
    final valid = taxa.where((t) => _binomial(t.scientificName) != null);
    for (final taxon in valid) {
      _accepted[_normalize(taxon.scientificName)] = _binomial(
        taxon.scientificName,
      )!;
    }
    for (final taxon in valid) {
      final key = _binomial(taxon.scientificName)!;
      for (final name in [taxon.scientificName, ...taxon.synonyms]) {
        final normalized = _normalize(name);
        _aliases.putIfAbsent(normalized, () => {}).add(key);
        final short = _binomial(name);
        if (short != null) _aliases.putIfAbsent(short, () => {}).add(key);
      }
    }
  }
  final _accepted = <String, String>{};
  final _aliases = <String, Set<String>>{};
  static String _normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  static final _uncertain = RegExp(
    r'\b(?:cf|cfr|aff|sp|spp|agg|aggr|group|complex|indet)\b',
  );
  static String? _binomial(String name) {
    final normalized = _normalize(name);
    if (_uncertain.hasMatch(normalized)) return null;
    return RegExp(
      r'^[a-zà-öø-ÿ][a-zà-öø-ÿ-]+ [a-zà-öø-ÿ][a-zà-öø-ÿ-]+(?:\s|$)',
    ).firstMatch(normalized)?.group(0)?.trim();
  }

  String? speciesKey(Observation observation) {
    if (observation.rank != IdentificationRank.species) return null;
    final name = _normalize(observation.taxonName ?? '');
    if (_binomial(name) == null) return null;
    if (_accepted.containsKey(name)) return _accepted[name];
    final exact = _aliases[name];
    if (exact != null) return exact.length == 1 ? exact.single : null;
    final short = _aliases[_binomial(name)];
    return short?.length == 1 ? short!.single : null;
  }

  FieldAchievementProgress progress(
    Iterable<Observation> observations, {
    Iterable<String> additionalSpecies = const [],
  }) {
    final keys = observations.map(speciesKey).whereType<String>().toSet();
    for (final name in additionalSpecies) {
      final key = speciesKey(
        Observation(
          id: 'plot-species',
          createdAt: DateTime(2000),
          rank: IdentificationRank.species,
          taxonName: name,
        ),
      );
      if (key != null) keys.add(key);
    }
    return FieldAchievementProgress(keys.length);
  }
}

class FieldAchievementProgress {
  const FieldAchievementProgress(this.speciesCount);
  final int speciesCount;
  bool unlocked(FieldAchievement achievement) =>
      speciesCount >= achievement.target;
  int get unlockedCount => fieldAchievements.where(unlocked).length;
  FieldAchievement? get next {
    for (final achievement in fieldAchievements) {
      if (!unlocked(achievement)) return achievement;
    }
    return null;
  }

  int remaining(FieldAchievement achievement) =>
      (achievement.target - speciesCount).clamp(0, achievement.target);
  double fraction(FieldAchievement achievement) =>
      (speciesCount / achievement.target).clamp(0, 1);
}
