import '../data/character_matrix_repository.dart';
import '../models/character_review.dart';
import 'character_dictionary.dart';
import 'physcia_review_engine.dart';
import 'structured_key_engine.dart';

/// Colour of the upper thallus only. Missing/conditional evidence stays unknown.
class ThallusColour {
  static const id = 'thallusColour';
  static const characterId = 'upper_surface_colour';
  static const question = StructuredQuestion(
    id,
    'Colore del tallo',
    'Qual è il colore della superficie superiore del tallo?',
    'Confronto indicativo con descrizioni e revisioni. Esclude il colore di apoteci, sorali, pruina, macule e pagina inferiore. Le schede con colori incerti o mancanti restano tra i candidati.',
    [
      StructuredChoice('light', 'Bianco / grigio', {
        'white',
        'grey',
        'whitish_grey',
        'bluish_grey',
        'lead_grey',
        'brownish_grey',
        'greenish_grey',
        'greenish_white',
        'cream',
      }),
      StructuredChoice('green', 'Verde / verdastro', {
        'green',
        'greenish_grey',
        'greenish_white',
      }),
      StructuredChoice('yellow', 'Giallo / crema', {'yellow', 'cream'}),
      StructuredChoice('orange', 'Arancione', {'orange'}),
      StructuredChoice('brown', 'Bruno / brunastro', {
        'brown',
        'brownish_grey',
      }),
      StructuredChoice('black', 'Nero', {'black'}),
    ],
  );

  static bool reliable(CharacterCell cell, MatrixTaxon row) {
    if (cell.stale || cell.status != 'recorded' || cell.values.isEmpty) {
      return false;
    }
    final supported = question.choices.expand((c) => c.sourceValues).toSet();
    if (!cell.values.every(supported.contains)) return false;
    if (cell.manualReview != null) {
      return PhysciaPilot.usable(
        cell.manualReview,
        row.taxon,
        PhysciaPilot.character(characterId)!,
      );
    }
    return (cell.review == 'description_colour' || cell.isStructured) &&
        cell.evidence.isNotEmpty &&
        cell.evidence.every((e) => e.matches(row.taxon));
  }

  static bool? matches(MatrixTaxon row, String selected) {
    final choice = question.choice(selected);
    final cell = row.cell(characterId);
    if (choice == null || !reliable(cell, row)) return null;
    return cell.values.any(choice.sourceValues.contains);
  }

  static int coverage(CharacterMatrix matrix) =>
      matrix.taxa.where((r) => reliable(r.cell(characterId), r)).length;

  static CharacterMatrix prepare(
    CharacterMatrix base,
    CharacterDictionary dictionary, {
    ReviewRegistry? registry,
  }) {
    final definition = dictionary.characters.singleWhere(
      (c) => c.id == characterId,
    );
    final character = MatrixCharacter(
      id: characterId,
      label: question.title,
      group: 'Morfologia',
      description: question.help,
      states: {for (final s in definition.states) s.value: s.label},
    );
    return CharacterMatrix(
      [...base.characters.where((c) => c.id != characterId), character],
      [
        for (final row in base.taxa)
          _prepareRow(row, dictionary, definition, registry),
      ],
    );
  }

  static MatrixTaxon _prepareRow(
    MatrixTaxon row,
    CharacterDictionary dictionary,
    DictionaryCharacter definition,
    ReviewRegistry? registry,
  ) {
    final review = registry?.latest(row.taxon.italicId!, characterId);
    CharacterCell cell;
    if (review != null) {
      // A draft, suspension, unknown or stale review must not fall back to extraction.
      cell = CharacterCell(
        status: 'recorded',
        review: 'manual_review',
        values: PhysciaPilot.character(characterId)!.selected(review.value),
        manualReview: review,
        stale: !review.matches(row.taxon),
      );
    } else if (row.cells.containsKey(characterId)) {
      cell = row.cell(characterId);
    } else {
      final text = row.taxon.description ?? '';
      final cutoff = RegExp(
        r'\b(?:note|nota)\s*:',
        caseSensitive: false,
      ).firstMatch(text)?.start;
      final analysis = dictionary.analyze(
        cutoff == null ? text : text.substring(0, cutoff),
        definition,
      );
      cell = !analysis.isCandidate
          ? const CharacterCell()
          : CharacterCell(
              status: 'recorded',
              review: 'description_colour',
              values: analysis.values,
              evidence: [
                for (final quote in analysis.hits.map((h) => h.quote).toSet())
                  CharacterEvidence(
                    field: 'description',
                    quote: quote,
                    rule: 'scoped-upper-thallus-colour-v1',
                  ),
              ],
            );
    }
    return MatrixTaxon(row.taxon, {...row.cells, characterId: cell});
  }
}
