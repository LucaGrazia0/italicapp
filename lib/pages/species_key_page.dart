import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:url_launcher/link.dart';
import '../app_store.dart';
import '../widgets/candidate_selection.dart';
import '../data/character_matrix_repository.dart';
import '../data/character_review_repository.dart';
import '../data/italic_api_traits_repository.dart';
import '../models/character_review.dart';
import '../models/identification_path.dart';
import '../models/observation.dart';
import '../services/italic_keymaker_client.dart';
import '../services/species_key_engine.dart';
import '../widgets/official_key_link.dart';
import 'italic_taxon_page.dart';
import 'reconstructed_key_page.dart';

class SpeciesKeyPage extends StatefulWidget {
  const SpeciesKeyPage({
    super.key,
    this.matrix,
    this.api,
    this.registry,
    this.reviewRepository,
    this.client,
    this.observation,
    this.store,
  }) : assert((observation == null) == (store == null));
  final CharacterMatrix? matrix;
  final ApiTraitsMatrix? api;
  final ReviewRegistry? registry;
  final CharacterReviewRepository? reviewRepository;
  final ItalicKeymakerClient? client;
  final Observation? observation;
  final AppStore? store;
  @override
  State<SpeciesKeyPage> createState() => _SpeciesKeyPageState();
}

class _SpeciesKeyPageState extends State<SpeciesKeyPage> {
  late final client = widget.client ?? ItalicKeymakerClient();
  final scroll = ScrollController();
  final changes = <Map<String, String>>[];
  Map<String, String> selections = {}, saved = {};
  SpeciesKeyEngine? engine;
  OfficialSpeciesKey? official;
  String? error;
  final warnings = <String>[];
  bool loading = true, failed = false, generating = false, saving = false;
  int visible = 20, revision = 0;
  bool get busy => generating || saving;
  bool get dirty => !mapEquals(selections, saved);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      failed = false;
      warnings.clear();
    });
    try {
      final matrix = widget.matrix ?? await CharacterMatrixRepository().load();
      ApiTraitsMatrix? api;
      try {
        api = widget.api ?? await ItalicApiTraitsRepository().load();
      } catch (_) {
        warnings.add(
          'Traits API non disponibili: questi confronti sono sospesi.',
        );
      }
      ReviewRegistry registry;
      try {
        registry =
            widget.registry ??
            ReviewRegistry(
              await (widget.reviewRepository ?? CharacterReviewRepository())
                  .all(),
            );
      } catch (_) {
        // We cannot safely use API morphology when a saved override may exist.
        registry = ReviewRegistry([]);
        api = null;
        warnings.add(
          'Revisioni locali non leggibili: i confronti morfologici sono sospesi per rispettare le tue modifiche. Riapri il percorso per riprovare.',
        );
      }
      final next = SpeciesKeyEngine(matrix, api: api, registry: registry);
      final path = widget.observation?.identificationPath;
      if (!mounted) return;
      setState(() {
        engine = next;
        if (path?.keyId == SpeciesKeyEngine.id) {
          selections = next.normalize(path!.selections);
        }
        saved = Map.of(selections);
      });
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  void dispose() {
    if (widget.client == null) client.close();
    scroll.dispose();
    super.dispose();
  }

  void _top() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && scroll.hasClients) {
      scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  });

  void _change(Map<String, String> next) {
    if (busy) return;
    final normalized = engine!.normalize(next);
    if (mapEquals(selections, normalized)) return;
    setState(() {
      changes.add(Map.of(selections));
      selections = normalized;
      visible = 20;
      revision++;
      official = null;
      error = null;
    });
    _top();
  }

  void _edit(String id) {
    final next = <String, String>{};
    for (final e in selections.entries) {
      if (e.key == id) break;
      next[e.key] = e.value;
    }
    _change(next);
  }

  Future<void> _generate(SpeciesResult result) async {
    if (busy) return;
    final snapshot = Map.of(selections);
    setState(() {
      generating = true;
      error = null;
    });
    try {
      final key = await client.generate(
        result.possible.map((c) => c.row.taxon.scientificName),
      );
      if (mounted && mapEquals(snapshot, selections)) {
        setState(() => official = key);
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? e.message
              : 'La chiave online non è disponibile in questo momento. Controlla la connessione e riprova.',
        );
      }
    } finally {
      if (mounted) setState(() => generating = false);
    }
  }

  IdentificationPath _candidatePath() => IdentificationPath(
    keyId: SpeciesKeyEngine.id,
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
    if (original == null || busy || !dirty) return;
    setState(() => saving = true);
    final snapshot = Map.of(selections);
    final path = snapshot.isEmpty
        ? null
        : IdentificationPath(
            keyId: SpeciesKeyEngine.id,
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
          const SnackBar(content: Text('Percorso salvato nell’osservazione.')),
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
    final result = engine?.evaluate(selections);
    final question = result == null ? null : engine!.next(selections, result);
    final answerEntries = selections.entries
        .where((e) => e.key != '_genus')
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Identifica una specie'),
        actions: [
          IconButton(
            key: const ValueKey('species-undo'),
            tooltip: 'Annulla ultima modifica',
            onPressed: busy || changes.isEmpty
                ? null
                : () {
                    setState(() {
                      selections = changes.removeLast();
                      visible = 20;
                      revision++;
                      official = null;
                      error = null;
                    });
                    _top();
                  },
            icon: const Icon(Icons.undo),
          ),
        ],
      ),
      bottomNavigationBar: widget.observation == null || loading || failed
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      !dirty
                          ? selections.isEmpty
                                ? 'Nessuna risposta da salvare.'
                                : 'Risposte salvate nell’osservazione.'
                          : widget.observation!.identificationPath != null
                          ? 'Al salvataggio sostituirai l’ultimo percorso di questa osservazione.'
                          : 'Risposte non ancora salvate.',
                    ),
                    const SizedBox(height: 6),
                    FilledButton.icon(
                      key: const ValueKey('species-save'),
                      onPressed: busy || !dirty ? null : _save,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(
                        saving
                            ? 'Salvataggio…'
                            : selections.isEmpty
                            ? 'Rimuovi percorso salvato'
                            : 'Salva percorso nell’osservazione',
                      ),
                    ),
                  ],
                ),
              ),
            ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Osserva il campione e scegli i caratteri che riconosci. Restringiamo i candidati con la matrice; poi puoi proseguire nei bivi della chiave ITALIC fino alla specie.',
              ),
              const SizedBox(height: 12),
              const Text(
                'La selezione locale funziona offline. La chiave ITALIC richiede internet. Un profilo compatibile deve essere verificato prima di attribuire il nome alla specie.',
              ),
              if (loading)
                const Padding(
                  padding: EdgeInsets.all(30),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (failed) ...[
                const Text('Impossibile caricare la matrice.'),
                TextButton(onPressed: _load, child: const Text('Riprova')),
              ] else ...[
                for (final warning in warnings)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(warning),
                  ),
                const SizedBox(height: 16),
                if (selections['_genus'] case final genus?)
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Chip(label: Text('Genere già riconosciuto: $genus')),
                      TextButton(
                        onPressed: busy ? null : () => _change({}),
                        child: const Text('Torna a tutti i taxa'),
                      ),
                    ],
                  )
                else
                  Autocomplete<String>(
                    key: ValueKey('species-genus-$revision'),
                    optionsBuilder: (value) => busy || value.text.trim().isEmpty
                        ? const Iterable<String>.empty()
                        : engine!.genera.where(
                            (g) => g.toLowerCase().startsWith(
                              value.text.trim().toLowerCase(),
                            ),
                          ),
                    onSelected: (genus) => _change({'_genus': genus}),
                    fieldViewBuilder:
                        (context, controller, focus, onSubmitted) => TextField(
                          key: const ValueKey('species-genus-input'),
                          controller: controller,
                          focusNode: focus,
                          enabled: !busy,
                          decoration: const InputDecoration(
                            labelText:
                                'Genere, se lo conosci già (facoltativo)',
                            hintText:
                                'Es. Physcia · seleziona un nome dai suggerimenti',
                            border: OutlineInputBorder(),
                          ),
                        ),
                  ),
                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${result!.possible.length} ${result.possible.length == 1 ? "taxon possibile" : "taxa possibili"}',
                          key: const ValueKey('species-count'),
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${result.matching.length} corrispondono ai dati · ${result.uncertain.length} con dati insufficienti · ${result.different.length} con differenze',
                        ),
                        const Text(
                          'I dati mancanti restano tra i possibili. Le differenze descrivono il profilo documentato; un substrato non elencato non prova un’assenza assoluta.',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (question != null) ...[
                  Text(
                    'Prossimo carattere · ${question.title}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    question.prompt,
                    key: const ValueKey('species-question'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(question.help),
                  const SizedBox(height: 16),
                  for (final choice in question.choices.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: OutlinedButton(
                        key: ValueKey('species-choice-${choice.key}'),
                        onPressed: busy
                            ? null
                            : () => _change({
                                ...selections,
                                question.id: choice.key,
                              }),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.all(16),
                          alignment: Alignment.centerLeft,
                        ),
                        child: Text(choice.value),
                      ),
                    ),
                  TextButton(
                    key: const ValueKey('species-skip'),
                    onPressed: busy
                        ? null
                        : () =>
                              _change({...selections, question.id: 'unknown'}),
                    child: const Text('Non so / salta'),
                  ),
                ] else ...[
                  Text(
                    result.oneProfile
                        ? 'Un solo profilo compatibile nei dati'
                        : result.possible.isEmpty
                        ? 'Le risposte non trovano un profilo compatibile'
                        : 'Prosegui con i bivi ITALIC',
                    key: const ValueKey('species-outcome'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    result.possible.isEmpty
                        ? 'Rivedi le risposte o annulla l’ultima scelta: possono esserci dati incompleti o caratteri da ricontrollare.'
                        : 'I caratteri disponibili non permettono altre separazioni affidabili in questo gruppo. Verifica i candidati nella chiave originale e nelle schede.',
                  ),
                ],
                const Divider(height: 30),
                _officialSection(result),
                if (answerEntries.isNotEmpty)
                  ExpansionTile(
                    key: ValueKey('species-history-$revision'),
                    tilePadding: EdgeInsets.zero,
                    title: Text('Le tue risposte (${answerEntries.length})'),
                    children: [
                      for (final entry in answerEntries)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            SpeciesKeyEngine.allQuestions
                                .firstWhere((q) => q.id == entry.key)
                                .title,
                          ),
                          subtitle: Text(
                            SpeciesKeyEngine.allQuestions
                                .firstWhere((q) => q.id == entry.key)
                                .label(entry.value),
                          ),
                          trailing: TextButton(
                            onPressed: busy ? null : () => _edit(entry.key),
                            child: const Text('Modifica'),
                          ),
                        ),
                    ],
                  ),
                if (selections.isNotEmpty)
                  TextButton.icon(
                    key: const ValueKey('species-restart'),
                    onPressed: busy ? null : () => _change({}),
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Ricomincia'),
                  ),
                const SizedBox(height: 16),
                Text(
                  'Candidati da verificare',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                for (final candidate in result.possible.take(visible))
                  _candidate(candidate),
                if (result.possible.length > visible)
                  TextButton(
                    onPressed: () => setState(() => visible += 20),
                    child: const Text('Mostra altri candidati'),
                  ),
                if (result.different.isNotEmpty)
                  ExpansionTile(
                    title: Text(
                      'Profili con differenze (${result.different.length})',
                    ),
                    children: [
                      for (final candidate in result.different.take(visible))
                        _candidate(candidate),
                      if (result.different.length > visible)
                        TextButton(
                          onPressed: () => setState(() => visible += 20),
                          child: const Text(
                            'Mostra altri profili con differenze',
                          ),
                        ),
                    ],
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openReconstructed() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReconstructedKeyPage(
          observation: widget.observation,
          store: widget.store,
        ),
      ),
    );
    if (mounted && widget.observation != null) {
      final path = widget.observation!.identificationPath;
      setState(
        () => saved = path?.keyId == SpeciesKeyEngine.id
            ? engine!.normalize(path!.selections)
            : {},
      );
    }
  }

  Widget _officialSection(SpeciesResult result) {
    final count = result.possible.length;
    final genera = result.possible
        .map((c) => c.row.taxon.scientificName.split(' ').first)
        .toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (genera.length == 1 && genera.single == 'Physcia') ...[
          FilledButton.icon(
            key: const ValueKey('open-reconstructed-physcia'),
            onPressed: busy ? null : _openReconstructed,
            icon: const Icon(Icons.account_tree_outlined),
            label: const Text('Segui i bivi Physcia nell’app'),
          ),
          const Text(
            'Percorso sul gruppo completo di 22 taxa, con caratteri collegati alla matrice e fonte consultabile a ogni bivio.',
          ),
          const SizedBox(height: 16),
        ],
        Text(
          'Continua nella chiave ufficiale',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        if (count >= 2 && count <= 100) ...[
          Text(
            'Invia a ITALIC i nomi dei $count taxa possibili, inclusi quelli con dati insufficienti. La chiave generata offre i bivi originali per il gruppo selezionato.',
          ),
          const SizedBox(height: 10),
          if (official == null)
            FilledButton.icon(
              key: const ValueKey('species-generate'),
              onPressed: busy ? null : () => _generate(result),
              icon: generating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.account_tree_outlined),
              label: Text(
                generating
                    ? 'Preparazione della chiave ITALIC…'
                    : 'Prepara la chiave ITALIC ($count taxa)',
              ),
            ),
        ] else if (count > 100)
          const Text(
            'Rispondi alle domande o indica un genere già riconosciuto per restringere il gruppo a un massimo di 100 taxa in questa app.',
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(error!, key: const ValueKey('species-online-error')),
          ),
        if (official case final key?) ...[
          Link(
            uri: key.url,
            target: LinkTarget.blank,
            builder: (context, follow) => FilledButton.icon(
              key: const ValueKey('species-official-link'),
              onPressed: follow,
              icon: const Icon(Icons.open_in_new),
              label: const Text('Apri chiave ITALIC fino alla specie'),
            ),
          ),
          Text(
            'Chiave richiesta per ${key.names.length} nomi. Controlla il gruppo nella pagina ITALIC.',
          ),
        ],
        if (genera.length == 1) GenusKeyLinks(genus: genera.single),
        if (count > 100)
          Link(
            uri: Uri.parse('https://italic.units.it/key-maker/info'),
            target: LinkTarget.blank,
            builder: (context, follow) => TextButton.icon(
              onPressed: follow,
              icon: const Icon(Icons.open_in_new),
              label: const Text('Apri Keymaker di ITALIC'),
            ),
          ),
      ],
    );
  }

  Widget _candidate(SpeciesCandidate candidate) => Card(
    child: ExpansionTile(
      key: ValueKey(
        'species-candidate-${candidate.row.taxon.italicId}-$revision',
      ),
      title: Text(
        candidate.row.taxon.scientificName,
        style: const TextStyle(fontStyle: FontStyle.italic),
      ),
      subtitle: Text(
        candidate.different
            ? 'Profilo documentato diverso'
            : candidate.uncertain
            ? 'Da verificare · dati insufficienti'
            : 'Corrisponde ai caratteri scelti',
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        for (final criterion in candidate.criteria)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${criterion.question.title}: ${criterion.label}'),
            subtitle: Text('${criterion.source}\n${criterion.quote}'),
          ),
        if (!candidate.different && widget.observation != null)
          CandidateSelectionButton(
            taxon: candidate.row.taxon,
            observation: widget.observation!,
            store: widget.store!,
            path: _candidatePath,
            disabled: busy,
            onBusy: _candidateBusy,
            onSaved: _candidateSaved,
          ),
        TextButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ItalicTaxonPage(taxon: candidate.row.taxon),
            ),
          ),
          icon: const Icon(Icons.menu_book_outlined),
          label: const Text('Apri scheda della specie'),
        ),
      ],
    ),
  );
}
