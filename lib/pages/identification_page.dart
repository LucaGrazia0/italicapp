import '../widgets/key_step_transition.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show mapEquals;

import '../app_store.dart';
import '../theme/app_theme.dart';
import '../data/identification_repository.dart';
import '../data/italic_reference_repository.dart';
import '../models/identification_path.dart';
import '../models/observation.dart';
import '../services/identification_engine.dart';
import '../widgets/official_key_link.dart';
import '../widgets/candidate_selection.dart';
import 'italic_taxon_page.dart';
import 'character_matrix_page.dart';
import 'structured_key_page.dart';
import 'physcia_review_page.dart';
import 'character_dictionary_page.dart';
import 'italic_api_traits_page.dart';
import '../services/structured_key_engine.dart';
import '../services/species_key_engine.dart';
import 'species_key_page.dart';
import 'reconstructed_key_page.dart';
import '../services/reconstructed_key.dart';
import 'general_keys_page.dart';

class DeterminationStartPage extends StatefulWidget {
  const DeterminationStartPage({
    super.key,
    this.observation,
    this.store,
    this.repository,
    this.toolsOnly = false,
  }) : assert((observation == null) == (store == null));
  final Observation? observation;
  final AppStore? store;
  final IdentificationRepository? repository;
  final bool toolsOnly;
  @override
  State<DeterminationStartPage> createState() => _DeterminationStartPageState();
}

class _DeterminationStartPageState extends State<DeterminationStartPage> {
  late final IdentificationRepository repo;
  bool loading = true;
  bool failed = false;
  @override
  void initState() {
    super.initState();
    repo = widget.repository ?? IdentificationRepository();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      await repo.load();
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _open(IdentificationKey definition) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DichotomousKeyPage(
          definition: definition,
          repository: repo,
          observation: widget.observation,
          store: widget.store,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openStructured() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StructuredKeyPage(
          observation: widget.observation,
          store: widget.store,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openSpecies() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SpeciesKeyPage(
          observation: widget.observation,
          store: widget.store,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (widget.toolsOnly) return _scaffold('Strumenti e dati', _tools());
    final path = widget.observation?.identificationPath;
    return _scaffold('Chiavi di determinazione', [
      Text(
        'Identifica il campione',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      Text(
        widget.observation == null
            ? 'Scegli i caratteri del campione e segui i bivi fino alla specie.'
            : 'Le risposte possono essere salvate e riprese da questa osservazione.',
      ),
      const SizedBox(height: 20),
      if (!loading && !failed) ...[
        if (path != null &&
            [
              StructuredKey.id,
              SpeciesKeyEngine.id,
              ReconstructedKey.id,
              ReconstructedKey.generalId,
              IdentificationKey.macro.id,
              repo.pilot.id,
            ].contains(path.keyId))
          _routeCard(
            'Riprendi il percorso salvato',
            '${path.answerCount} ${path.answerCount == 1 ? "risposta registrata" : "risposte registrate"}',
            Icons.history,
            () => path.keyId == StructuredKey.id
                ? _openStructured()
                : path.keyId == SpeciesKeyEngine.id
                ? _openSpecies()
                : [
                    ReconstructedKey.id,
                    ReconstructedKey.generalId,
                  ].contains(path.keyId)
                ? Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReconstructedKeyPage(
                        general: path.keyId == ReconstructedKey.generalId,
                        observation: widget.observation,
                        store: widget.store,
                      ),
                    ),
                  ).then((_) {
                    if (mounted) setState(() {});
                  })
                : _open(
                    path.keyId == repo.pilot.id
                        ? repo.pilot
                        : IdentificationKey.macro,
                  ),
            key: const ValueKey('resume-key'),
          ),
      ],
      _routeCard(
        'Chiavi · tutti i taxa',
        'Segui i bivi nell’app, scegli un genere oppure cerca una specie per studiare i suoi percorsi e i casi mancanti.',
        Icons.account_tree_outlined,
        () =>
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GeneralKeysPage(
                  observation: widget.observation,
                  store: widget.store,
                ),
              ),
            ).then((_) {
              if (mounted) setState(() {});
            }),
        key: const ValueKey('open-general-keys'),
        primary: true,
      ),
    ]);
  }

  List<Widget> _tools() => [
    if (loading)
      const Padding(
        padding: EdgeInsets.all(16),
        child: LinearProgressIndicator(),
      )
    else if (failed) ...[
      const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Strumenti aggiuntivi non disponibili. Riprova a caricare i dati.',
        ),
      ),
      TextButton(onPressed: _load, child: const Text('Riprova')),
    ] else ...[
      _routeCard(
        'Identifica una specie',
        'Scegli i caratteri, confronta i candidati e continua nei bivi originali ITALIC fino alla specie.',
        Icons.route_outlined,
        _openSpecies,
        key: const ValueKey('open-species-key'),
      ),
      _routeCard(
        'Physcia · revisione e prova',
        'Revisiona i caratteri dei 22 taxa: tallo, colori, lobi, presenza, forme e tipi, e prova la chiave con i dati confermati manualmente.',
        Icons.fact_check_outlined,
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PhysciaReviewPage()),
        ),
        key: const ValueKey('open-physcia-review'),
      ),
      _routeCard(
        'Matrice specie × caratteri',
        'Confronta i taxa e consulta valori, dati mancanti e citazioni dei caratteri.',
        Icons.table_chart_outlined,
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CharacterMatrixPage()),
        ),
        key: const ValueKey('open-character-matrix'),
      ),
      _routeCard(
        'Matrice dei traits · ITALIC API',
        'Consulta 29 stati API e le indicazioni riproduttive di soredi o simili e isidi o simili, con fonte e discrepanze.',
        Icons.dataset_outlined,
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ItalicApiTraitsPage()),
        ),
        key: const ValueKey('open-api-traits-matrix'),
      ),
      _routeCard(
        'Dizionario dei caratteri',
        'Cerca presenza, forme e tipi nelle descrizioni: sorali, soredi, isidi, ciglia, rizine e apoteci.',
        Icons.manage_search,
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CharacterDictionaryPage()),
        ),
        key: const ValueKey('open-character-dictionary'),
      ),
      _routeCard(
        'Chiavi originali ITALIC',
        '${repo.genusKeys.length} voci per genere. Segui i bivi originali nella copia offline.',
        Icons.menu_book_outlined,
        () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OfficialKeysPage(entries: repo.genusKeys),
          ),
        ),
        key: const ValueKey('open-official-keys'),
      ),
    ],
  ];
}

class DichotomousKeyPage extends StatefulWidget {
  const DichotomousKeyPage({
    super.key,
    required this.definition,
    this.repository,
    this.observation,
    this.store,
  }) : assert((observation == null) == (store == null));
  final IdentificationKey definition;
  final IdentificationRepository? repository;
  final Observation? observation;
  final AppStore? store;
  @override
  State<DichotomousKeyPage> createState() => _DichotomousKeyPageState();
}

class _DichotomousKeyPageState extends State<DichotomousKeyPage> {
  late final IdentificationRepository repo;
  Map<String, KeyAnswer> answers = {};
  bool loading = true, failed = false, confirmedGenus = false, saving = false;
  Map<String, KeyAnswer> savedAnswers = {};
  final changes = <Map<String, KeyAnswer>>[];
  final scrollController = ScrollController();
  bool get dirty => !mapEquals(answers, savedAnswers);
  int visible = 20;
  IdentificationKey get definition => widget.definition;

  @override
  void initState() {
    super.initState();
    repo = widget.repository ?? IdentificationRepository();
    final saved = widget.observation?.identificationPath;
    if (saved?.keyId == definition.id) {
      answers = definition.normalize(saved!.answers);
      savedAnswers = Map.of(answers);
      confirmedGenus = answers.isNotEmpty;
    }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      await repo.load();
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  void _change(Map<String, KeyAnswer> next) {
    final normalized = definition.normalize(next);
    if (mapEquals(answers, normalized)) return;
    setState(() {
      changes.add(Map.of(answers));
      answers = normalized;
      visible = 20;
    });
    _scrollToStart();
  }

  void _scrollToStart() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scrollController.hasClients) {
        scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _choose(KeyQuestion question, KeyAnswer answer) =>
      _change({...answers, question.id: answer});

  void _rewind(String id) {
    final index = definition.questions.indexWhere((q) => q.id == id);
    final next = Map.of(answers);
    for (final question in definition.questions.skip(index)) {
      next.remove(question.id);
    }
    _change(next);
  }

  void _undo() {
    setState(() {
      answers = changes.removeLast();
      visible = 20;
    });
    _scrollToStart();
  }

  IdentificationPath _candidatePath() => IdentificationPath(
    keyId: definition.id,
    answers: Map.of(answers),
    savedAt: DateTime.now(),
  );
  void _candidateBusy(bool busy) {
    if (mounted) setState(() => saving = busy);
  }

  void _candidateSaved(IdentificationPath path) {
    if (mounted) setState(() => savedAnswers = Map.of(path.answers));
  }

  Future<void> _save() async {
    final original = widget.observation;
    if (original == null || saving || !dirty) return;
    setState(() => saving = true);
    final snapshot = Map.of(answers);
    final path = snapshot.isEmpty
        ? null
        : IdentificationPath(
            keyId: definition.id,
            answers: snapshot,
            savedAt: DateTime.now(),
          );
    final updated = Observation.fromMap(original.toMap())
      ..identificationPath = path;
    try {
      await widget.store!.save(updated);
      original.identificationPath = path;
      if (mounted) {
        setState(() => savedAnswers = snapshot);
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
              'Salvataggio non riuscito. Le risposte restano disponibili: riprova.',
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
    final answerCount =
        '${answers.length} ${answers.length == 1 ? "risposta" : "risposte"}';
    final question = definition.next(answers);
    final result = IdentificationEngine().evaluate(
      repo.taxa,
      definition,
      answers,
    );
    return _scaffold(
      definition.title,
      [
        if (!definition.isMacro)
          const Chip(label: Text('Sperimentale · da revisionare')),
        Text(definition.scope),
        if (widget.observation?.substrate != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Substrato annotato: ${widget.observation!.substrate}. Il percorso segue i caratteri osservati.',
            ),
          ),
        const SizedBox(height: 16),
        if (loading)
          const Center(child: CircularProgressIndicator())
        else if (failed) ...[
          const Text('Impossibile caricare la checklist locale.'),
          TextButton(onPressed: _load, child: const Text('Riprova')),
        ] else if (!definition.isMacro && !confirmedGenus) ...[
          CheckboxListTile(
            key: const ValueKey('confirm-genus'),
            title: Text(
              'Il campione è già attribuito al genere ${definition.genus}',
            ),
            value: confirmedGenus,
            onChanged: (value) =>
                setState(() => confirmedGenus = value ?? false),
          ),
          const Text(
            'Se il genere è incerto, torna a Macrocaratteri o consulta le chiavi originali ITALIC.',
          ),
        ] else ...[
          Text(
            question == null
                ? 'Percorso completato · $answerCount'
                : 'Bivio ${definition.questions.indexOf(question) + 1} di ${definition.questions.length} · $answerCount',
            key: const ValueKey('key-progress'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: question == null
                ? 1
                : answers.length / definition.questions.length,
            semanticsLabel: 'Avanzamento del percorso',
          ),
          if (answers.containsValue(KeyAnswer.unknown))
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Le risposte «Non so» non escludono candidati.'),
            ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                result.activeCriteria == 0
                    ? '${result.supported.length + result.unresolved.length} taxa nel percorso · nessun carattere verificato'
                    : '${result.supported.length} ${result.supported.length == 1 ? "candidato coerente" : "candidati coerenti"} · '
                          '${result.unresolved.length} con dati insufficienti · '
                          '${result.excluded} ${result.excluded == 1 ? "escluso" : "esclusi"}',
                key: const ValueKey('key-candidate-count'),
              ),
            ),
          ),
          KeyStepTransition(
            step: '${question?.id ?? 'complete'}:${answers.length}',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (question != null) ...[
                  Text(
                    'Bivio ${definition.questions.indexOf(question) + 1} · ${question.title}',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    question.prompt,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 10),
                  Text(question.help),
                  const SizedBox(height: 20),
                  FilledButton(
                    key: const ValueKey('answer-a'),
                    onPressed: saving
                        ? null
                        : () => _choose(question, KeyAnswer.a),
                    child: Text('A · ${question.a}'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    key: const ValueKey('answer-b'),
                    onPressed: saving
                        ? null
                        : () => _choose(question, KeyAnswer.b),
                    child: Text('B · ${question.b}'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    key: const ValueKey('answer-unknown'),
                    onPressed: saving
                        ? null
                        : () => _choose(question, KeyAnswer.unknown),
                    child: const Text('Non so / Non verificato'),
                  ),
                  if (answers.isNotEmpty)
                    TextButton.icon(
                      onPressed: saving
                          ? null
                          : () => _rewind(answers.keys.last),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Torna al bivio precedente'),
                    ),
                ] else ...[
                  Text(
                    result.activeCriteria == 0
                        ? 'Nessun carattere verificato'
                        : result.supported.isEmpty
                        ? 'Risposte da rivedere o dati insufficienti'
                        : 'Candidati da verificare',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Un candidato coerente con questo percorso non è un’identificazione definitiva. '
                    'Apri la scheda e confronta i caratteri con la chiave originale.',
                  ),
                  if (result.supported.isEmpty && result.unresolved.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'Nessun taxon soddisfa insieme le risposte. Rivedi i bivi, la struttura osservata e l’attribuzione del genere.',
                      ),
                    ),
                ],
              ],
            ),
          ),
          if (question != null)
            RemainingCandidates(
              key: ValueKey(
                'legacy-remaining-${question.id}-${answers.values.join()}',
              ),
              taxa: [...result.supported, ...result.unresolved],
              uncertainIds: {for (final t in result.unresolved) t.italicId!},
              observation: widget.observation,
              store: widget.store,
              path: _candidatePath,
              disabled: saving,
              onBusy: _candidateBusy,
              onSaved: _candidateSaved,
            ),
          if (answers.isNotEmpty) ...[
            const Divider(height: 28),
            Text(
              'Il tuo percorso',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final q in definition.questions.where(
              (q) => answers.containsKey(q.id),
            ))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(q.title),
                subtitle: Text(q.label(answers[q.id]!)),
                trailing: TextButton(
                  onPressed: saving ? null : () => _rewind(q.id),
                  child: const Text('Modifica'),
                ),
              ),
          ],
          if (question == null) ...[
            const SizedBox(height: 20),
            for (final taxon in result.supported.take(visible))
              _candidate(taxon),
            if (result.supported.length > visible)
              TextButton(
                onPressed: () => setState(() => visible += 20),
                child: const Text('Mostra altri candidati'),
              ),
            if (result.unresolved.isNotEmpty)
              ExpansionTile(
                key: ValueKey(
                  'unresolved-${answers.values.map((a) => a.name).join()}',
                ),
                title: Text('Dati insufficienti (${result.unresolved.length})'),
                subtitle: const Text(
                  'Un dato mancante non equivale all’assenza del carattere.',
                ),
                children: [
                  for (final taxon in result.unresolved.take(visible))
                    _candidate(taxon),
                  if (result.unresolved.length > visible)
                    TextButton(
                      onPressed: () => setState(() => visible += 20),
                      child: const Text(
                        'Mostra altri taxa con dati insufficienti',
                      ),
                    ),
                ],
              ),
            if (!definition.isMacro && result.excludedTaxa.isNotEmpty)
              ExpansionTile(
                key: ValueKey(
                  'excluded-${answers.values.map((a) => a.name).join()}',
                ),
                title: Text('Confronta i taxa esclusi (${result.excluded})'),
                subtitle: const Text(
                  'Vedi quali risposte contrastano con i caratteri documentati.',
                ),
                children: [
                  for (final taxon in result.excludedTaxa.take(visible))
                    _candidate(taxon, selectable: false),
                  if (result.excluded > visible)
                    TextButton(
                      onPressed: () => setState(() => visible += 20),
                      child: const Text('Mostra altri taxa esclusi'),
                    ),
                ],
              ),
            if (definition.genus != null)
              GenusKeyLinks(genus: definition.genus!),
            TextButton.icon(
              key: const ValueKey('restart-key'),
              onPressed: saving ? null : () => _change({}),
              icon: const Icon(Icons.restart_alt),
              label: const Text('Ricomincia il percorso'),
            ),
          ],
        ],
      ],
      controller: scrollController,
      actions: [
        IconButton(
          key: const ValueKey('undo-key-change'),
          tooltip: 'Annulla ultima modifica',
          onPressed: saving || changes.isEmpty ? null : _undo,
          icon: const Icon(Icons.undo),
        ),
      ],
      bottomBar: widget.observation == null || loading || failed
          ? null
          : _saveBar(),
    );
  }

  Widget _saveBar() => SafeArea(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            dirty
                ? answers.isEmpty
                      ? 'Il percorso salvato sarà rimosso al salvataggio.'
                      : 'Modifiche da salvare prima di uscire.'
                : savedAnswers.isNotEmpty
                ? 'Risposte salvate nell’osservazione.'
                : 'Le risposte saranno collegate a questa osservazione.',
            key: const ValueKey('path-save-status'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          FilledButton.icon(
            key: const ValueKey('save-identification-path'),
            onPressed: saving || !dirty ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(
              saving
                  ? 'Salvataggio…'
                  : dirty && answers.isEmpty
                  ? 'Rimuovi percorso salvato'
                  : dirty
                  ? 'Salva percorso'
                  : savedAnswers.isNotEmpty
                  ? 'Percorso salvato'
                  : 'Salva percorso',
            ),
          ),
        ],
      ),
    ),
  );

  Widget _candidate(ItalicTaxon taxon, {bool selectable = true}) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            taxon.scientificName,
            style: const TextStyle(
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ItalicTaxonPage(taxon: taxon)),
            ),
            icon: const Icon(Icons.menu_book_outlined),
            label: const Text('Scheda ITALIC'),
          ),
          if (selectable && widget.observation != null)
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
            key: ValueKey(
              'evidence-${taxon.italicId}-${answers.values.map((a) => a.name).join()}',
            ),
            title: const Text('Confronto dei caratteri'),
            children: [
              for (final question in definition.questions.where(
                (q) => answers.containsKey(q.id),
              ))
                _comparison(taxon, question),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _comparison(ItalicTaxon taxon, KeyQuestion question) {
    final chosen = answers[question.id]!;
    final documented = question.documentedAnswer(taxon);
    final skipped = chosen == KeyAnswer.unknown;
    final missing = documented == null;
    final conflict = !skipped && !missing && chosen != documented;
    final status = skipped
        ? 'Non verificato'
        : missing
        ? 'Dato mancante'
        : conflict
        ? 'Discordante'
        : 'Coerente';
    final color = conflict ? Theme.of(context).colorScheme.error : null;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      leading: Icon(
        skipped || missing
            ? Icons.help_outline
            : conflict
            ? Icons.close
            : Icons.check,
        color: color,
        semanticLabel: status,
      ),
      title: Text(
        '${question.title} · $status',
        style: TextStyle(color: color),
      ),
      subtitle: Text(
        [
          'La tua risposta: ${question.label(chosen)}',
          if (documented != null) 'ITALIC: ${question.label(documented)}',
          if (missing) 'Carattere non verificabile nei dati disponibili.',
          if (!definition.isMacro && !missing)
            'ITALIC ID ${taxon.italicId}: “${question.evidence[taxon.italicId]}”',
          if (skipped) 'Questa risposta non contribuisce alla selezione.',
        ].join('\n\n'),
      ),
    );
  }
}

class OfficialKeysPage extends StatefulWidget {
  const OfficialKeysPage({super.key, required this.entries});
  final List<GenusKey> entries;
  @override
  State<OfficialKeysPage> createState() => _OfficialKeysPageState();
}

class _OfficialKeysPageState extends State<OfficialKeysPage> {
  String query = '';
  final searchController = TextEditingController();

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries
        .where(
          (entry) => '${entry.genus} ${entry.name}'.toLowerCase().contains(
            query.trim().toLowerCase(),
          ),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Chiavi originali ITALIC')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Apri le chiavi originali nell’app, senza connessione. Più generi possono condividere la stessa chiave: testi, numerazione e ambito restano quelli della fonte.',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('genus-key-search'),
                      controller: searchController,
                      onChanged: (value) => setState(() => query = value),
                      decoration: InputDecoration(
                        labelText: 'Cerca un genere',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: query.isEmpty
                            ? null
                            : IconButton(
                                key: const ValueKey('clear-genus-search'),
                                tooltip: 'Cancella ricerca',
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  searchController.clear();
                                  setState(() => query = '');
                                },
                              ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${entries.length} ${entries.length == 1 ? "voce del catalogo" : "voci del catalogo"}',
                    ),
                  ],
                ),
              ),
              Expanded(
                child: entries.isEmpty
                    ? const Center(
                        child: Text('Nessuna chiave per questa ricerca.'),
                      )
                    : ListView.builder(
                        itemCount: entries.length,
                        itemBuilder: (_, index) => Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 4,
                          ),
                          child: OfficialKeyLink(entry: entries[index]),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _routeCard(
  String title,
  String subtitle,
  IconData icon,
  VoidCallback open, {
  Key? key,
  bool primary = false,
}) => Card(
  color: primary ? AppTheme.forest : null,
  child: ListTile(
    key: key,
    contentPadding: primary ? const EdgeInsets.all(20) : null,
    iconColor: primary ? Colors.white : null,
    textColor: primary ? Colors.white : null,
    titleTextStyle: primary
        ? const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          )
        : null,
    subtitleTextStyle: primary
        ? const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 14,
            height: 1.4,
            color: Colors.white,
          )
        : null,
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right),
    onTap: open,
  ),
);

Widget _scaffold(
  String title,
  List<Widget> children, {
  ScrollController? controller,
  List<Widget>? actions,
  Widget? bottomBar,
}) => Scaffold(
  appBar: AppBar(title: Text(title), actions: actions),
  bottomNavigationBar: bottomBar,
  body: Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: ListView(
        controller: controller,
        padding: const EdgeInsets.all(20),
        children: children,
      ),
    ),
  ),
);
