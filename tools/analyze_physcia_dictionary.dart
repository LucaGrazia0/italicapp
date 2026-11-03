import 'dart:convert';
import 'dart:io';
import 'package:italicapp/services/character_dictionary.dart';

// Runs the same search engine as the app; writes proposals, never user reviews.
void main() {
  final root = File.fromUri(Platform.script).parent.parent;
  final dictionary = CharacterDictionary.fromMap(
    jsonDecode(
          File(
            '${root.path}/assets/italic/character_dictionary_v3.json',
          ).readAsStringSync(),
        )
        as Map,
  );
  final snapshot =
      jsonDecode(
            File(
              '${root.path}/assets/italic/italic_checklist.json',
            ).readAsStringSync(),
          )
          as Map;
  final taxa = (snapshot['taxa'] as List)
      .cast<Map>()
      .where(
        (r) => (r['scientificName'] as String).split(' ').first == 'Physcia',
      )
      .toList();
  final rows = <Map<String, Object?>>[];
  final counts = <String, Map<String, int>>{
    for (final c in dictionary.characters)
      c.id: {'candidate': 0, 'needs_review': 0, 'not_documented': 0},
  };
  var candidates = 0, uncertain = 0, missing = 0;
  for (final taxon in taxa) {
    final text = taxon['description'] as String? ?? '';
    final cells = <Map<String, Object?>>[];
    for (final c in dictionary.characters) {
      final analysis = dictionary.analyze(text, c);
      final hits = analysis.hits;
      final stable = analysis.isCandidate;
      final status = analysis.status;
      counts[c.id]![status] = counts[c.id]![status]! + 1;
      if (stable) {
        candidates++;
      } else if (hits.isEmpty) {
        missing++;
      } else {
        uncertain++;
      }
      final value = analysis.value;
      final label = !stable
          ? null
          : c.kind == 'type'
          ? c.states
                .where((s) => analysis.values.contains(s.value))
                .map((s) => s.label)
                .join(' / ')
          : value == 'present'
          ? 'Presente'
          : 'Assenza esplicita';
      cells.add({
        'characterId': c.id,
        'label': c.label,
        'status': status,
        'suggestedValue': value,
        'suggestedValues': analysis.values,
        'suggestedLabel': label,
        'review': 'automatic_proposal_only',
        'evidence': [
          for (final h in hits)
            {
              'quote': h.quote,
              'start': h.start,
              'end': h.end,
              'term': h.term,
              'status': h.status,
              'type': h.state?.value,
            },
        ],
      });
    }
    rows.add({
      'italicId': taxon['italicId'],
      'scientificName': taxon['scientificName'],
      'sourceUrl': taxon['sourceUrl'],
      'characters': cells,
    });
  }
  final output = {
    'schemaVersion': 1,
    'scope': 'Physcia',
    'review': 'automatic_proposals_only',
    'taxa': taxa.length,
    'characterGroups': dictionary.characters.length,
    'summary': {
      'candidates': candidates,
      'needsReview': uncertain,
      'notDocumented': missing,
    },
    'byCharacter': counts,
    'rows': rows,
  };
  File(
    '${root.path}/reports/physcia_dictionary_proposals.json',
  ).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(output)}\n',
  );
  final md = <String>[
    '# Prima lettura automatica delle descrizioni Physcia',
    '',
    '${taxa.length} taxa × ${dictionary.characters.length} gruppi = ${taxa.length * dictionary.characters.length} confronti.',
    '',
    '- $candidates proposte con uno o più stati esplicitamente documentati secondo le regole del dizionario.',
    '- $uncertain casi con menzioni, condizioni, negazioni o più stati da controllare.',
    '- $missing casi senza un carattere documentabile con il vocabolario attuale.',
    '',
    'Questi numeri misurano la copertura testuale, non l’accuratezza scientifica.',
    'Le proposte non sono revisioni confermate. Nessun record dell’utente è stato modificato.',
    'Un’informazione non trovata non viene trasformata in assenza.',
    '',
    '| Carattere | Proposta documentata | Da controllare | Non documentato |',
    '|---|---:|---:|---:|',
    for (final c in dictionary.characters)
      '| ${c.label} | ${counts[c.id]!['candidate']} | ${counts[c.id]!['needs_review']} | ${counts[c.id]!['not_documented']} |',
    '',
    '## Proposte per taxon',
    '',
  ];
  for (final row in rows) {
    md.add('### ${row['scientificName']} · ID ${row['italicId']}');
    md.add('');
    final cells = (row['characters'] as List).cast<Map<String, Object?>>();
    for (final cell in cells.where((c) => c['status'] == 'candidate')) {
      final quote = ((cell['evidence'] as List).first as Map)['quote'];
      md.add('- **${cell['label']}: ${cell['suggestedLabel']}** — “$quote”');
    }
    final review = cells
        .where((c) => c['status'] == 'needs_review')
        .map((c) => c['label'])
        .join(', ');
    final absent = cells
        .where((c) => c['status'] == 'not_documented')
        .map((c) => c['label'])
        .join(', ');
    if (review.isNotEmpty) md.add('- Da controllare: $review.');
    if (absent.isNotEmpty) md.add('- Non documentato dal dizionario: $absent.');
    md.add('');
  }
  File(
    '${root.path}/reports/physcia_dictionary_proposals.md',
  ).writeAsStringSync('${md.join('\n')}\n');
  stdout.writeln(jsonEncode(output['summary']));
  stdout.writeln(
    'Report: ${root.path}/reports/physcia_dictionary_proposals.md',
  );
}
