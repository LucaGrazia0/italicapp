import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import '../app_store.dart';
import '../widgets/candidate_selection.dart';
import '../data/character_matrix_repository.dart';
import '../models/identification_path.dart';
import '../models/observation.dart';
import '../services/structured_key_engine.dart';
import 'italic_taxon_page.dart';

class StructuredKeyPage extends StatefulWidget {
  const StructuredKeyPage({
    super.key,
    this.matrix,
    this.repository,
    this.observation,
    this.store,
  }) : assert((observation == null) == (store == null));
  final CharacterMatrix? matrix;
  final CharacterMatrixRepository? repository;
  final Observation? observation;
  final AppStore? store;
  @override
  State<StructuredKeyPage> createState() => _StructuredKeyPageState();
}

class _StructuredKeyPageState extends State<StructuredKeyPage> {
  final engine = StructuredKey();
  final scroll = ScrollController();
  final changes = <Map<String, String>>[];
  Map<String, String> selections = {}, saved = {};
  CharacterMatrix? matrix;
  bool loading = true, failed = false, saving = false;
  int visible = 20;
  bool get dirty => !mapEquals(selections, saved);

  @override
  void initState() {
    super.initState();
    final path = widget.observation?.identificationPath;
    if (path?.keyId == StructuredKey.id) {
      selections = engine.normalize(path!.selections);
      saved = Map.of(selections);
    }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      final data =
          widget.matrix ??
          await (widget.repository ?? CharacterMatrixRepository()).load();
      final ids = data.characters.map((c) => c.id).toSet();
      if (!StructuredKey.questions.every((q) => ids.contains(q.id))) {
        throw const FormatException('Required structured columns missing');
      }
      if (mounted) setState(() => matrix = data);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  void _top() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && scroll.hasClients) {
      scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  });

  void _change(Map<String, String> next) {
    final normalized = engine.normalize(next);
    if (mapEquals(selections, normalized)) return;
    setState(() {
      changes.add(Map.of(selections));
      selections = normalized;
      visible = 20;
    });
    _top();
  }

  void _edit(String id) {
    final next = Map.of(selections);
    final index = StructuredKey.questions.indexWhere((q) => q.id == id);
    for (final q in StructuredKey.questions.skip(index)) {
      next.remove(q.id);
    }
    _change(next);
  }

  IdentificationPath _candidatePath() => IdentificationPath(
    keyId: StructuredKey.id,
    answers: const {},
    selections: Map.of(selections),
    savedAt: DateTime.now(),
  );
  void _candidateBusy(bool value) {
    if (mounted) setState(() => saving = value);
  }

  void _candidateSaved(IdentificationPath path) {
    if (mounted) setState(() => saved = Map.of(path.selections));
  }

  Future<void> _save() async {
    final original = widget.observation;
    if (original == null || saving || !dirty) return;
    setState(() => saving = true);
    final snapshot = Map.of(selections);
    final path = snapshot.isEmpty
        ? null
        : IdentificationPath(
            keyId: StructuredKey.id,
            answers: const {},
            selections: snapshot,
            savedAt: DateTime.now(),
          );
    final updated = Observation.fromMap(original.toMap())
      ..identificationPath = path;
    try {
      await widget.store!.save(updated);
      original.identificationPath = path;
      if (mounted) {
        setState(() => saved = snapshot);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              path == null
                  ? 'Percorso rimosso dall’osservazione.'
                  : 'Percorso salvato nell’osservazione.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Salvataggio non riuscito. Il percorso precedente resta intatto: riprova.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final question = engine.next(selections);
    final result = matrix == null ? null : engine.evaluate(matrix!, selections);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Percorso guidato · 4 caratteri'),
        actions: [
          IconButton(
            key: const ValueKey('structured-undo'),
            tooltip: 'Annulla ultima modifica',
            onPressed: saving || changes.isEmpty
                ? null
                : () {
                    setState(() {
                      selections = changes.removeLast();
                      visible = 20;
                    });
                    _top();
                  },
            icon: const Icon(Icons.undo),
          ),
        ],
      ),
      bottomNavigationBar: widget.observation == null || loading || failed
          ? null
          : _saveBar(),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Selezione preliminare dai quattro gruppi di dati strutturati ITALIC. Il risultato è un profilo compatibile da verificare, non una determinazione definitiva.',
              ),
              const SizedBox(height: 16),
              if (loading)
                const Center(child: CircularProgressIndicator())
              else if (failed) ...[
                const Text('Impossibile caricare i dati strutturati.'),
                TextButton(onPressed: _load, child: const Text('Riprova')),
              ] else ...[
                Text(
                  question == null
                      ? 'Percorso completato · 4 risposte'
                      : 'Passaggio ${selections.length + 1} di 4 · ${question.title}',
                  key: const ValueKey('structured-progress'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: selections.length / StructuredKey.questions.length,
                  semanticsLabel: 'Avanzamento del percorso',
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '${result!.matching.length} ${result.matching.length == 1 ? "profilo corrispondente" : "profili corrispondenti"} · ${result.uncertain.length} con dati insufficienti · ${result.different.length} con differenze',
                      key: const ValueKey('structured-count'),
                    ),
                  ),
                ),
                if (result.activeCriteria == 0)
                  const Text(
                    'Nessun carattere verificato: tutti i taxa restano da valutare.',
                  ),
                if (selections.containsValue(StructuredKey.unknown))
                  const Text(
                    'Le risposte «Non so» non restringono i candidati.',
                  ),
                const SizedBox(height: 16),
                if (question != null) ...[
                  Text(
                    question.prompt,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 10),
                  Text(question.help),
                  if (question.id == 'substrata' &&
                      widget.observation?.substrate != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Substrato annotato nel diario: ${widget.observation!.substrate}',
                      ),
                    ),
                  const SizedBox(height: 18),
                  for (final choice in question.choices)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: OutlinedButton(
                        key: ValueKey('structured-choice-${choice.id}'),
                        onPressed: saving
                            ? null
                            : () => _change({
                                ...selections,
                                question.id: choice.id,
                              }),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(choice.label),
                        ),
                      ),
                    ),
                  TextButton(
                    key: const ValueKey('structured-unknown'),
                    onPressed: saving
                        ? null
                        : () => _change({
                            ...selections,
                            question.id: StructuredKey.unknown,
                          }),
                    child: const Text('Non so / Non verificato'),
                  ),
                ] else ...[
                  Text(
                    result.activeCriteria == 0
                        ? 'Nessun carattere verificato'
                        : result.matching.isEmpty
                        ? 'Profilo da rivedere o dati insufficienti'
                        : 'Taxa da verificare',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Le differenze indicano un profilo documentato diverso o un substrato non documentato. Non dimostrano l’assenza assoluta del taxon o di strutture riproduttive.',
                  ),
                ],
                if (selections.isNotEmpty) ...[
                  const Divider(height: 28),
                  ExpansionTile(
                    key: ValueKey(
                      'structured-history-${selections.length}-${question == null}',
                    ),
                    initiallyExpanded: question == null,
                    tilePadding: EdgeInsets.zero,
                    title: Text('Le tue risposte (${selections.length})'),
                    children: [
                      for (final q in StructuredKey.questions.where(
                        (q) => selections.containsKey(q.id),
                      ))
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(q.title),
                          subtitle: Text(q.label(selections[q.id]!)),
                          trailing: TextButton(
                            key: ValueKey('structured-edit-${q.id}'),
                            onPressed: saving ? null : () => _edit(q.id),
                            child: const Text('Modifica'),
                          ),
                        ),
                    ],
                  ),
                  TextButton.icon(
                    key: const ValueKey('structured-restart'),
                    onPressed: saving ? null : () => _change({}),
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Ricomincia il percorso'),
                  ),
                ],
                if (question != null)
                  RemainingCandidates(
                    key: ValueKey(
                      'structured-remaining-${selections.values.join()}',
                    ),
                    taxa: [
                      for (final a in [...result.matching, ...result.uncertain])
                        a.row.taxon,
                    ],
                    uncertainIds: {
                      for (final a in result.uncertain) a.row.taxon.italicId!,
                    },
                    observation: widget.observation,
                    store: widget.store,
                    path: _candidatePath,
                    disabled: saving,
                    onBusy: _candidateBusy,
                    onSaved: _candidateSaved,
                  ),
                if (question == null) ...[
                  const SizedBox(height: 12),
                  for (final assessment in result.matching.take(visible))
                    _candidate(assessment),
                  if (result.matching.length > visible)
                    TextButton(
                      onPressed: () => setState(() => visible += 20),
                      child: const Text('Mostra altri taxa corrispondenti'),
                    ),
                  if (result.uncertain.isNotEmpty)
                    ExpansionTile(
                      title: Text(
                        'Dati insufficienti (${result.uncertain.length})',
                      ),
                      subtitle: const Text(
                        'Un dato mancante non è un’assenza.',
                      ),
                      children: [
                        for (final assessment in result.uncertain.take(visible))
                          _candidate(assessment),
                        if (result.uncertain.length > visible)
                          TextButton(
                            onPressed: () => setState(() => visible += 20),
                            child: const Text(
                              'Mostra altri taxa con dati insufficienti',
                            ),
                          ),
                      ],
                    ),
                  if (result.different.isNotEmpty)
                    ExpansionTile(
                      title: Text(
                        'Profilo diverso o substrato non documentato (${result.different.length})',
                      ),
                      children: [
                        for (final assessment in result.different.take(visible))
                          _candidate(assessment),
                        if (result.different.length > visible)
                          TextButton(
                            onPressed: () => setState(() => visible += 20),
                            child: const Text('Mostra altri profili diversi'),
                          ),
                      ],
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _saveBar() {
    final replacing =
        widget.observation?.identificationPath != null &&
        widget.observation!.identificationPath!.keyId != StructuredKey.id;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              dirty
                  ? selections.isEmpty
                        ? 'Il percorso salvato sarà rimosso al salvataggio.'
                        : replacing
                        ? 'Il salvataggio sostituirà l’ultimo percorso dell’osservazione.'
                        : 'Modifiche da salvare prima di uscire.'
                  : saved.isNotEmpty
                  ? 'Risposte salvate nell’osservazione.'
                  : 'Salva le risposte per riprenderle dal diario.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            FilledButton.icon(
              key: const ValueKey('save-structured-path'),
              onPressed: saving || !dirty ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(
                saving
                    ? 'Salvataggio…'
                    : dirty && selections.isEmpty
                    ? 'Rimuovi percorso salvato'
                    : dirty
                    ? 'Salva percorso nell’osservazione'
                    : saved.isNotEmpty
                    ? 'Percorso salvato'
                    : 'Salva percorso',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _candidate(StructuredAssessment assessment) {
    final taxon = assessment.row.taxon;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              taxon.scientificName,
              style: const TextStyle(
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.bold,
              ),
            ),
            TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ItalicTaxonPage(taxon: taxon),
                ),
              ),
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('Scheda ITALIC'),
            ),
            if (!assessment.differs && widget.observation != null)
              CandidateSelectionButton(
                taxon: taxon,
                observation: widget.observation!,
                store: widget.store!,
                path: _candidatePath,
                disabled: saving,
                onBusy: _candidateBusy,
                onSaved: _candidateSaved,
              ),
            ExpansionTile(
              key: ValueKey('structured-evidence-${taxon.italicId}'),
              title: const Text('Confronto dei 4 caratteri'),
              children: [
                for (final q in StructuredKey.questions.where(
                  (q) => selections.containsKey(q.id),
                ))
                  _criterion(assessment, q),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _criterion(
    StructuredAssessment assessment,
    StructuredQuestion question,
  ) {
    final value = selections[question.id]!;
    final skipped = value == StructuredKey.unknown;
    final criterion = skipped
        ? null
        : assessment.criteria.singleWhere((c) => c.question.id == question.id);
    final character = matrix!.characters.singleWhere(
      (c) => c.id == question.id,
    );
    final cell = assessment.row.cell(question.id);
    final usable =
        criterion != null && criterion.status != StructuredMatch.unknown;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        '${question.title} · ${criterion?.label ?? "Non verificato"}',
      ),
      subtitle: Text(
        [
          'La tua risposta: ${question.label(value)}',
          if (skipped) 'Questa risposta non contribuisce alla selezione.',
          if (usable)
            'ITALIC: ${cell.values.map((v) => character.states[v] ?? v).join(" / ")}',
          if (usable)
            ...cell.evidence.map((e) => 'Fonte ${e.field}: “${e.quote}”'),
          if (!skipped && !usable)
            'Dato strutturato assente o non verificabile: nessuna assenza viene dedotta.',
        ].join('\n\n'),
      ),
    );
  }
}
