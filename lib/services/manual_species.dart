import '../models/observation.dart';
import '../data/italic_reference_repository.dart';

IdentificationRank manualNameRank(String value) {
  if (RegExp(
    r'\b(?:cf|cfr|aff|sp|spp|agg|indet)\b|\?',
    caseSensitive: false,
  ).hasMatch(value)) {
    return IdentificationRank.undetermined;
  }
  if (RegExp(
    r'^[A-ZÀ-ÖØ-Þ][a-zà-öø-ÿ-]+\s+[a-zà-öø-ÿ-]+(?:\s|$)',
  ).hasMatch(value)) {
    return IdentificationRank.species;
  }
  if (RegExp(r'^[A-ZÀ-ÖØ-Þ][a-zà-öø-ÿ-]+$').hasMatch(value)) {
    return value.endsWith('aceae')
        ? IdentificationRank.family
        : IdentificationRank.genus;
  }
  return IdentificationRank.undetermined;
}

Observation assignSpecies(Observation original, ItalicTaxon taxon) =>
    original.copy()
      ..taxonName = taxon.scientificName
      ..taxonItalicId = taxon.italicId
      ..rank = manualNameRank(taxon.scientificName)
      ..identificationMethod = 'manual';
