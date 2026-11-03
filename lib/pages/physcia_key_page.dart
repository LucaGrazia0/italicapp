import 'package:flutter/material.dart';
import '../data/character_matrix_repository.dart';
import '../models/character_review.dart';
import '../services/physcia_review_engine.dart';
import '../widgets/official_key_link.dart';
import 'italic_taxon_page.dart';

class PhysciaKeyPage extends StatefulWidget {
  const PhysciaKeyPage({
    super.key,
    required this.matrix,
    required this.registry,
  });
  final CharacterMatrix matrix;
  final ReviewRegistry registry;
  @override
  State<PhysciaKeyPage> createState() => _PhysciaKeyPageState();
}

class _PhysciaKeyPageState extends State<PhysciaKeyPage> {
  bool confirmed = false;
  final selections = <String, String>{};
  @override
  Widget build(BuildContext context) {
    final result = PhysciaReviewEngine().evaluate(
      widget.matrix,
      widget.registry,
      selections,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Physcia · prova revisionata')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Chip(label: Text('Sperimentale · revisioni locali')),
              const Text(
                'Questa prova usa solo le ultime revisioni manuali con valore stabile e fonte invariata. Non certifica un’identificazione; i taxa con dati insufficienti rimangono tra le possibilità.',
              ),
              const SizedBox(height: 12),
              if (!confirmed)
                CheckboxListTile(
                  key: const ValueKey('physcia-confirm-genus'),
                  value: false,
                  title: const Text(
                    'Il campione è già attribuito al genere Physcia',
                  ),
                  onChanged: (v) => setState(() => confirmed = v ?? false),
                )
              else ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '${result.matching.length} corrispondenti ai dati revisionati · ${result.uncertain.length} non valutabili · ${result.different.length} con differenze',
                      key: const ValueKey('physcia-key-count'),
                    ),
                  ),
                ),
                const Text(
                  '«Non so», celle non revisionate, variabili o con fonte cambiata non restringono i candidati. Una revisione con più colori o forme corrisponde se comprende il valore scelto: consulta la citazione per condizioni e localizzazioni.',
                ),
                const SizedBox(height: 16),
                for (final c in PhysciaPilot.characters)
                  if (PhysciaPilot.absentSampleParent(c.id, selections) != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: InputDecorator(
                        decoration: InputDecoration(labelText: c.label),
                        child: Text(
                          'Non applicabile · ${PhysciaPilot.character(PhysciaPilot.absentSampleParent(c.id, selections)!)!.label}: assente',
                          key: ValueKey('physcia-not-applicable-${c.id}'),
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(
                          'physcia-select-${c.id}-${selections[c.id] ?? "unknown"}',
                        ),
                        initialValue: selections[c.id] ?? 'unknown',
                        isExpanded: true,
                        decoration: InputDecoration(labelText: c.label),
                        items: [
                          const DropdownMenuItem(
                            value: 'unknown',
                            child: Text('Non so / Non verificato'),
                          ),
                          ...c.values.entries
                              .where((e) => c.stable(e.key))
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e.key,
                                  child: Text(e.value),
                                ),
                              ),
                        ],
                        onChanged: (v) => setState(() {
                          selections[c.id] = v!;
                          if (v == 'absent') {
                            for (final dependent in PhysciaPilot.characters) {
                              if (PhysciaPilot.parents(
                                dependent.id,
                              ).contains(c.id)) {
                                selections.remove(dependent.id);
                              }
                            }
                          }
                        }),
                      ),
                    ),
                TextButton.icon(
                  key: const ValueKey('reset-physcia-key'),
                  onPressed: () => setState(selections.clear),
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Azzera le risposte'),
                ),
                if (selections.values.any((v) => v != 'unknown')) ...[
                  const Divider(height: 28),
                  Text(
                    'Taxa da verificare',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  for (final candidate in result.matching)
                    _candidate(candidate),
                  if (result.uncertain.isNotEmpty)
                    ExpansionTile(
                      initiallyExpanded: result.matching.isEmpty,
                      title: Text(
                        'Non valutabili (${result.uncertain.length})',
                      ),
                      children: [
                        for (final candidate in result.uncertain)
                          _candidate(candidate),
                      ],
                    ),
                  if (result.different.isNotEmpty)
                    ExpansionTile(
                      title: Text(
                        'Differenze documentate (${result.different.length})',
                      ),
                      children: [
                        for (final candidate in result.different)
                          _candidate(candidate),
                      ],
                    ),
                ],
                const GenusKeyLinks(genus: 'Physcia'),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _candidate(ReviewedCandidate candidate) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            candidate.row.taxon.scientificName,
            style: const TextStyle(
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.bold,
            ),
          ),
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ItalicTaxonPage(taxon: candidate.row.taxon),
              ),
            ),
            child: const Text('Scheda ITALIC'),
          ),
          ExpansionTile(
            title: const Text('Evidenze revisionate'),
            children: [
              for (final c in candidate.criteria)
                ListTile(
                  title: Text(
                    '${c.character.label} · ${c.matches == null
                        ? "Non valutabile"
                        : c.matches!
                        ? "Corrisponde"
                        : "Differente"}',
                  ),
                  subtitle: Text(
                    c.notApplicable
                        ? 'Non applicabile: ${PhysciaPilot.absenceLabel(c.review!)}.\n${c.review!.statusLabel} · ${c.review!.reviewer} · v${c.review!.version}'
                        : c.matches == null
                        ? 'Ultima revisione stabile e verificabile non disponibile. Nessuna assenza dedotta.'
                        : 'La tua scelta: ${c.character.labelFor(c.selection)}\nRevisione: ${c.character.labelFor(c.review!.value)}\n${c.review!.reviewer} · ${c.review!.createdAt.toLocal()} · v${c.review!.version}\n“${c.review!.quote}”',
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}
