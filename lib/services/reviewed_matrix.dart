import '../data/character_matrix_repository.dart';
import '../models/character_review.dart';
import 'physcia_review_engine.dart';

/// Rebuilds the displayed matrix from the original plus the latest saved edits.
/// Drafts and stale edits remain visible; only the review engine decides which
/// values can filter candidates. The original matrix and history stay intact.
CharacterMatrix reviewedMatrix(CharacterMatrix base, ReviewRegistry registry) {
  final characters = [
    for (final c in base.characters)
      if (PhysciaPilot.character(c.id) case final pilot?)
        MatrixCharacter(
          id: c.id,
          label: c.label,
          group: c.group,
          description: c.description,
          states: {...c.states, ...pilot.values},
        )
      else
        c,
    for (final pilot in PhysciaPilot.characters)
      if (!base.characters.any((c) => c.id == pilot.id))
        MatrixCharacter(
          id: pilot.id,
          label: pilot.label,
          group: 'Morfologia',
          description: pilot.help,
          states: pilot.values,
        ),
  ];
  final latest = <String, CharacterReview>{};
  for (final record in registry.records) {
    final old = latest[record.cellKey];
    if (old == null ||
        record.version > old.version ||
        (record.version == old.version && record.id.compareTo(old.id) > 0)) {
      latest[record.cellKey] = record;
    }
  }
  return CharacterMatrix(characters, [
    for (final row in base.taxa)
      MatrixTaxon(row.taxon, {
        ...row.cells,
        if (PhysciaPilot.inScope(row.taxon))
          for (final pilot in PhysciaPilot.characters)
            if (latest['${row.taxon.italicId}:${pilot.id}'] case final record?)
              pilot.id: CharacterCell(
                status: record.value == 'unknown' ? 'unknown' : 'recorded',
                values: pilot.selected(record.value),
                review: 'manual_review',
                manualReview: record,
                stale:
                    !record.matches(row.taxon) ||
                    !pilot.validValue(record.value),
                evidence: [
                  if (record.quote.isNotEmpty)
                    CharacterEvidence(
                      field: 'description',
                      quote: record.quote,
                      rule: 'manual-review-${record.id}',
                    ),
                ],
              ),
        if (PhysciaPilot.inScope(row.taxon))
          for (final pilot in PhysciaPilot.characters)
            if (PhysciaPilot.absenceFor(registry, row.taxon, pilot.id)
                case final absence?)
              pilot.id: CharacterCell(
                status: 'not_applicable',
                review: 'structure_dependency',
                applicabilityReview: absence,
              ),
      }),
  ]);
}
