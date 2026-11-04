import 'dart:convert';
import 'scientific_data.dart';
import 'italic_reference_repository.dart';
import '../models/character_review.dart';
import 'revision_cache.dart';

class MatrixCharacter {
  const MatrixCharacter({
    required this.id,
    required this.label,
    required this.group,
    required this.description,
    required this.states,
  });
  final String id, label, group, description;
  final Map<String, String> states;
  factory MatrixCharacter.fromMap(Map data) => MatrixCharacter(
    id: data['id'] as String,
    label: data['label'] as String,
    group: data['group'] as String,
    description: data['description'] as String,
    states: Map<String, String>.from(data['states'] as Map),
  );
}

class CharacterEvidence {
  const CharacterEvidence({
    required this.field,
    required this.quote,
    required this.rule,
  });
  final String field, quote, rule;
  factory CharacterEvidence.fromMap(Map data) => CharacterEvidence(
    field: data['field'] as String,
    quote: data['quote'] as String,
    rule: data['rule'] as String,
  );

  bool matches(ItalicTaxon taxon) {
    final String? source;
    if (field == 'description') {
      source = taxon.description;
    } else if (field.startsWith('ecologyCodes.')) {
      source = taxon.ecologyCodes[field.substring('ecologyCodes.'.length)];
    } else {
      return false;
    }
    return quote.isNotEmpty &&
        source != null &&
        (field == 'description' ? source.contains(quote) : source == quote);
  }
}

class CharacterCell {
  const CharacterCell({
    this.status = 'unknown',
    this.values = const [],
    this.review = '',
    this.evidence = const [],
    this.stale = false,
    this.manualReview,
    this.applicabilityReview,
  });
  final String status, review;
  final List<String> values;
  final List<CharacterEvidence> evidence;
  final bool stale;
  final CharacterReview? manualReview;
  final CharacterReview? applicabilityReview;
  bool get isNotApplicable => status == 'not_applicable';
  bool get isUnknown => status == 'unknown';
  bool get isStructured => review == 'structured_source' && !isUnknown;
  String get reviewLabel => applicabilityReview != null
      ? 'Struttura registrata come assente · ${applicabilityReview!.statusLabel}'
      : manualReview?.statusLabel ??
            switch (review) {
              'structured_source' => 'Trascritto da dati strutturati ITALIC',
              'needs_expert_review' =>
                'Codifica manuale del pilota · da revisionare',
              _ => 'Estrazione automatica · da revisionare',
            };

  factory CharacterCell.read(
    Map data,
    MatrixCharacter character,
    ItalicTaxon taxon,
  ) {
    final evidence = (data['evidence'] as List)
        .cast<Map>()
        .map(CharacterEvidence.fromMap)
        .toList();
    final values = (data['values'] as List).cast<String>();
    final status = data['status'] as String;
    final valid =
        ['recorded', 'ambiguous'].contains(status) &&
        (status == 'ambiguous' || values.isNotEmpty) &&
        values.every(character.states.containsKey) &&
        evidence.isNotEmpty &&
        evidence.every((proof) => proof.matches(taxon));
    if (!valid) return const CharacterCell(stale: true);
    return CharacterCell(
      status: status,
      values: values,
      review: data['review'] as String,
      evidence: evidence,
    );
  }

  String label(MatrixCharacter character) {
    if (stale) return 'Fonte da aggiornare';
    if (isNotApplicable) return 'Non applicabile';
    if (manualReview != null) {
      return values
          .map((v) => character.states[v] ?? 'Non codificato')
          .join(' / ');
    }
    if (isUnknown) return 'Non codificato';
    final labels = values.map((v) => character.states[v]!).join(' / ');
    if (status == 'ambiguous') {
      return labels.isEmpty ? 'Da chiarire' : 'Da chiarire: $labels';
    }
    return labels;
  }
}

class MatrixTaxon {
  const MatrixTaxon(this.taxon, this.cells);
  final ItalicTaxon taxon;
  final Map<String, CharacterCell> cells;
  CharacterCell cell(String id) => cells[id] ?? const CharacterCell();
}

class CharacterMatrix {
  const CharacterMatrix(this.characters, this.taxa);
  final List<MatrixCharacter> characters;
  final List<MatrixTaxon> taxa;
  int get availableCells => taxa.fold(
    0,
    (sum, row) => sum + row.cells.values.where((c) => !c.isUnknown).length,
  );
  int get staleCells => taxa.fold(
    0,
    (sum, row) => sum + row.cells.values.where((c) => c.stale).length,
  );

  factory CharacterMatrix.fromMap(Map data, List<ItalicTaxon> reference) {
    if (data['schemaVersion'] != 1) {
      throw const FormatException('Unsupported matrix version');
    }
    final characters = (data['characters'] as List)
        .cast<Map>()
        .map(MatrixCharacter.fromMap)
        .toList();
    final byCharacter = {
      for (final character in characters) character.id: character,
    };
    if (byCharacter.length != characters.length) {
      throw const FormatException('Duplicate character');
    }
    final byTaxon = {for (final taxon in reference) taxon.italicId: taxon};
    final seen = <int>{};
    final rows = <MatrixTaxon>[];
    for (final raw in (data['taxa'] as List).cast<Map>()) {
      final id = raw['italicId'] as int;
      if (!seen.add(id)) throw const FormatException('Duplicate taxon');
      final taxon = byTaxon[id];
      if (taxon == null || taxon.scientificName != raw['scientificName']) {
        throw const FormatException(
          'Taxon identity changed: regenerate matrix',
        );
      }
      final cells = <String, CharacterCell>{};
      for (final entry in (raw['cells'] as Map).entries) {
        final character = byCharacter[entry.key];
        if (character == null) throw const FormatException('Unknown character');
        cells[character.id] = CharacterCell.read(
          entry.value as Map,
          character,
          taxon,
        );
      }
      rows.add(MatrixTaxon(taxon, cells));
    }
    if (rows.length != reference.length) {
      throw const FormatException('Matrix coverage changed');
    }
    return CharacterMatrix(characters, rows);
  }
}

class CharacterMatrixRepository {
  static final _cache = RevisionCache<CharacterMatrix>();
  // A versioned filename also refreshes existing browser HTTP caches.
  static const asset = 'assets/italic/character_matrix_v2.json';
  Future<CharacterMatrix> load({int? revision}) =>
      _cache.load(_read, revision: revision);
  Future<CharacterMatrix> _read(int revision) async {
    final reference = ItalicReferenceRepository();
    await reference.load(revision: revision);
    final data =
        jsonDecode(await ScientificData.loadString(asset, revision: revision))
            as Map;
    return CharacterMatrix.fromMap(data, reference.taxa);
  }
}
