import 'dart:convert';
import 'scientific_data.dart';
import 'italic_reference_repository.dart';

class ApiTraitCharacter {
  const ApiTraitCharacter(this.id, this.label);
  final String id, label;
  bool get isReproduction => id.startsWith('reproduction_');
  String get group => switch (id) {
    _ when isReproduction => 'Riproduzione',
    _ when id.startsWith('growth_form_') => 'Tallo',
    _ when id.startsWith('photobiont_') => 'Fotobionte',
    _ when id.startsWith('ascocarps_') => 'Ascocarpi',
    _ when id.startsWith('apothecia_') => 'Apoteci',
    _ when id.startsWith('ascospores_') => 'Ascospore',
    _ when id.startsWith('cortex_') => 'Reazione K',
    _ => 'Altri stati',
  };
}

class ApiTraitConflict {
  const ApiTraitConflict(this.field, this.quote);
  final String field, quote;
  String get label => switch (field) {
    'ascospores_per_ascus' => 'Numero di spore per asco',
    'cortex_K' => 'Reazione K della corteccia',
    _ => field,
  };
  bool concerns(String characterId) => switch (field) {
    'ascospores_per_ascus' => characterId.endsWith('_per_ascus'),
    'cortex_K' => characterId.startsWith('cortex_k_'),
    _ => field == characterId,
  };
}

class ApiTraitRow {
  const ApiTraitRow({
    required this.taxon,
    required this.values,
    required this.sourceUrl,
    required this.retrievedAt,
    required this.conflicts,
    required this.warning,
    required this.schemaIssueCount,
    this.descriptionChanged = false,
    this.reproductionEvidence,
    this.reproductionChanged = false,
  });
  final ItalicTaxon taxon;
  final Map<String, int?> values;
  final String sourceUrl, retrievedAt, warning;
  final List<ApiTraitConflict> conflicts;
  final int schemaIssueCount;
  final bool descriptionChanged;
  final Map<String, dynamic>? reproductionEvidence;
  final bool reproductionChanged;
  bool get needsComparison =>
      conflicts.isNotEmpty ||
      warning.isNotEmpty ||
      schemaIssueCount > 0 ||
      descriptionChanged ||
      reproductionChanged ||
      values.entries
          .where((e) => !e.key.startsWith('reproduction_'))
          .every((e) => e.value == null);
}

class ApiTraitsMatrix {
  const ApiTraitsMatrix(this.characters, this.taxa);
  final List<ApiTraitCharacter> characters;
  final List<ApiTraitRow> taxa;
  int get recordedCells => taxa.fold(
    0,
    (sum, row) => sum + row.values.values.where((v) => v != null).length,
  );
  int get comparisonRows => taxa.where((r) => r.needsComparison).length;
  int get populatedTaxa => taxa
      .where(
        (r) => r.values.entries.any(
          (e) => !e.key.startsWith('reproduction_') && e.value != null,
        ),
      )
      .length;
  int get sorediaIndications => taxa
      .where((r) => r.values['reproduction_soredia_or_similar'] == 1)
      .length;
  int get isidiaIndications =>
      taxa.where((r) => r.values['reproduction_isidia_or_similar'] == 1).length;

  factory ApiTraitsMatrix.fromMap(Map data, List<ItalicTaxon> reference) {
    if (data['schemaVersion'] != 2 ||
        data['requestedTaxa'] != reference.length ||
        data['source'] != 'ITALIC API v2 traits-pa') {
      throw const FormatException('Unexpected API matrix version or coverage');
    }
    final characters = (data['characters'] as List).cast<Map>().map((c) {
      return ApiTraitCharacter(c['id'] as String, c['label'] as String);
    }).toList();
    final keys = characters.map((c) => c.id).toSet();
    if (keys.isEmpty || keys.length != characters.length) {
      throw const FormatException('Invalid API columns');
    }
    final byId = {for (final taxon in reference) taxon.italicId: taxon};
    final seen = <int>{};
    final rows = <ApiTraitRow>[];
    String normalized(String name) =>
        name.trim().replaceAll(RegExp(r'\s+'), ' ');
    for (final raw in (data['taxa'] as List).cast<Map>()) {
      final id = raw['italicId'] as int;
      final taxon = byId[id];
      if (!seen.add(id) ||
          taxon == null ||
          raw['scientificName'] != taxon.scientificName ||
          normalized(raw['apiName'] as String) !=
              normalized(taxon.scientificName)) {
        throw const FormatException('API taxon identity mismatch');
      }
      final cells = raw['cells'] as Map;
      if (cells.length != keys.length || !cells.keys.every(keys.contains)) {
        throw const FormatException('API columns changed');
      }
      final values = <String, int?>{};
      for (final key in keys) {
        final value = cells[key];
        if (value != null && (value is! int || (value != 0 && value != 1))) {
          throw const FormatException('API value is not binary');
        }
        values[key] = value as int?;
      }
      final reproduction = Map<String, dynamic>.from(
        raw['reproductionEvidence'] as Map,
      );
      final code = taxon.ecologyCodes['reproductiveStrategy'] ?? '';
      final reproductionChanged =
          reproduction['field'] != 'ecologyCodes.reproductiveStrategy' ||
          reproduction['quoteField'] != 'reproductiveStrategy' ||
          reproduction['code'] != code ||
          reproduction['quote'] != (taxon.reproductiveStrategy ?? '') ||
          reproduction['sourceUrl'] != (taxon.sourceUrl ?? '') ||
          reproduction['status'] == 'source_mismatch';
      for (final key in [
        'reproduction_soredia_or_similar',
        'reproduction_isidia_or_similar',
      ]) {
        if (values[key] == 0) {
          throw const FormatException('Reproduction does not imply absence');
        }
        if (reproductionChanged) {
          values[key] = null;
        } else if (values[key] == 1 &&
            (reproduction['status'] != 'documented' ||
                (key == 'reproduction_soredia_or_similar'
                    ? !['A.s', 'S-A.s'].contains(code)
                    : code != 'A.i'))) {
          throw const FormatException(
            'Invalid reproductive strategy indication',
          );
        }
      }
      final source = raw['source'] as Map;
      final url = source['url'] as String;
      final retrieved = source['retrievedAt'] as String;
      if (url != 'https://italic.units.it/api/v2/traits-pa/$id' ||
          DateTime.tryParse(retrieved) == null ||
          source['httpStatus'] != 200) {
        throw const FormatException('API provenance mismatch');
      }
      final conflicts = <ApiTraitConflict>[];
      var descriptionChanged = false;
      for (final conflict
          in (raw['descriptionConflicts'] as List).cast<Map>()) {
        final quote = conflict['descriptionQuote'] as String;
        // A conflict belongs to the description snapshot used by the importer.
        if (quote.isNotEmpty && (taxon.description?.contains(quote) ?? false)) {
          conflicts.add(ApiTraitConflict(conflict['field'] as String, quote));
        } else {
          descriptionChanged = true;
        }
      }
      rows.add(
        ApiTraitRow(
          taxon: taxon,
          values: values,
          sourceUrl: url,
          retrievedAt: retrieved,
          conflicts: conflicts,
          warning: (raw['warnings'] as String?) ?? '',
          schemaIssueCount: (raw['schemaIssues'] as List).length,
          descriptionChanged: descriptionChanged,
          reproductionEvidence: reproduction,
          reproductionChanged: reproductionChanged,
        ),
      );
    }
    if (rows.length != reference.length) {
      throw const FormatException('Incomplete API matrix');
    }
    return ApiTraitsMatrix(characters, rows);
  }
}

class ItalicApiTraitsRepository {
  static const asset = 'assets/italic/api_traits_matrix_v2.json';
  Future<ApiTraitsMatrix> load({int? revision}) async {
    final reference = ItalicReferenceRepository();
    await reference.load(revision: revision);
    final raw =
        jsonDecode(await ScientificData.loadString(asset, revision: revision))
            as Map;
    return ApiTraitsMatrix.fromMap(raw, reference.taxa);
  }
}
