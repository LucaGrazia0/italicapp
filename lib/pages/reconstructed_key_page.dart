import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:url_launcher/link.dart';
import '../app_store.dart';
import '../data/character_matrix_repository.dart';
import '../data/italic_api_traits_repository.dart';
import '../data/scientific_data.dart';
import '../services/key_prefilter.dart';
import '../widgets/candidate_selection.dart';
import '../models/identification_path.dart';
import '../models/observation.dart';
import '../services/physcia_review_engine.dart';
import '../services/reconstructed_key.dart';
import 'italic_taxon_page.dart';
import 'character_dictionary_page.dart';

class ReconstructedKeyPage extends StatefulWidget {
  const ReconstructedKeyPage({
    super.key,
    this.definition,
    this.observation,
    this.store,
    this.general = false,
    this.genus,
    this.startFresh = false,
    this.preFilters = const {},
    this.matrix,
    this.apiMatrix,
  }) : assert((observation == null) == (store == null));
  final ReconstructedKey? definition;
  final Observation? observation;
  final AppStore? store;
  final bool general, startFresh;
  final String? genus;
  final Map<String, String> preFilters;
  final CharacterMatrix? matrix;
  final ApiTraitsMatrix? apiMatrix;
  @override
  State<ReconstructedKeyPage> createState() => _ReconstructedKeyPageState();
}

class _ReconstructedKeyPageState extends State<ReconstructedKeyPage> {
  ReconstructedKey? definition;
  Map<String, String> selections = {}, saved = {};
  final history = <Map<String, String>>[];
  final scroll = ScrollController();
  bool failed = false, saving = false;
  int revision = 0;
  int? dataRevision;
  final candidatesAnchor = GlobalKey();
  final coupletAnchor = GlobalKey();
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      failed = false;
    });
    try {
      final path = widget.observation?.identificationPath;
      final expectedKeyId =
          widget.definition?.identity ??
          (widget.general ? ReconstructedKey.generalId : ReconstructedKey.id);
      final requestedEdition =
          !widget.startFresh && path?.keyId == expectedKeyId
          ? (path!.dataRevision ?? ScientificData.legacyRevision)
          : null;
      dataRevision = requestedEdition ?? ScientificData.currentRevision;
      var key =
          widget.definition ??
          await (widget.general
              ? ReconstructedKey.loadGeneral(revision: requestedEdition)
              : ReconstructedKey.load(revision: requestedEdition));
      final restoring = !widget.startFresh && path?.keyId == key.identity;
      final genus =
          widget.genus ?? (restoring ? path!.selections['_genus'] : null);
      if (key.general && genus != null) key = key.forGenus(genus);
      final filters = KeyPrefilter.normalize(
        restoring ? KeyPrefilter.restore(path!.selections) : widget.preFilters,
      );
      if (filters.isNotEmpty) {
        final matrix =
            widget.matrix ??
            await CharacterMatrixRepository().load(revision: requestedEdition);
        final api = filters.keys.any((k) => k.startsWith('binary:'))
            ? (widget.apiMatrix ??
                  await ItalicApiTraitsRepository().load(
                    revision: requestedEdition,
                  ))
            : null;
        final comparison = KeyPrefilter(key, matrix, filters, apiMatrix: api);
        if (comparison.coveredLocal == 0) {
          throw const FormatException('No local candidates');
        }
        key = key.filtered(comparison.eligible, filters);
      }
      if (!mounted) return;
      setState(() {
        definition = key;
        selections = restoring
            ? key.normalize(path!.selections)
            : key.normalize({});
        saved = restoring ? Map.of(selections) : {};
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusCouplet());
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  void _change(Map<String, String> next) {
    if (saving) return;
    setState(() {
      history.add(Map.of(selections));
      selections = definition!.normalize(next);
      revision++;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusCouplet();
    });
  }

  void _focusCouplet() {
    if (!mounted || !scroll.hasClients) return;
    final target = coupletAnchor.currentContext;
    if (target != null && target.mounted) {
      Scrollable.ensureVisible(
        target,
        alignment: 0.04,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } else {
      scroll.jumpTo(0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final ctx = coupletAnchor.currentContext;
          if (ctx != null && ctx.mounted) {
            Scrollable.ensureVisible(
              ctx,
              alignment: 0.04,
              duration: const Duration(milliseconds: 220),
            );
          }
        }
      });
    }
  }

  void _edit(String node) {
    final next = <String, String>{};
    for (final e in selections.entries) {
      if (e.key == node) break;
      next[e.key] = e.value;
    }
    _change(next);
  }

  void _back() {
    if (saving) return;
    final key = definition!;
    final node = key.current(selections);
    final steps = key.trail(selections);
    if (selections[node.id] == 'unknown') {
      _edit(node.id);
    } else if (steps.isNotEmpty) {
      _edit(steps.last.node.id);
    } else {
      Navigator.maybePop(context);
    }
  }

  Future<void> _showCandidates() async {
    if (candidatesAnchor.currentContext == null && scroll.hasClients) {
      await scroll.animateTo(
        scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
    if (!mounted) return;
    final target = candidatesAnchor.currentContext;
    if (target != null && target.mounted) {
      await Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 200),
      );
    }
  }

  IdentificationPath _candidatePath() => IdentificationPath(
    keyId: definition!.identity,
    dataRevision: dataRevision,
    answers: const {},
    selections: Map.of(selections),
    savedAt: DateTime.now(),
  );

  void _candidateBusy(bool busy) {
    if (mounted) setState(() => saving = busy);
  }

  void _candidateSaved(IdentificationPath path) {
    if (mounted) setState(() => saved = Map.of(path.selections));
  }

  Future<void> _save() async {
    if (saving || mapEquals(saved, selections)) return;
    setState(() => saving = true);
    final original = widget.observation!;
    final snapshot = Map.of(selections);
    final path = snapshot.isEmpty
        ? null
        : IdentificationPath(
            keyId: definition!.identity,
            dataRevision: dataRevision,
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
              'Salvataggio non riuscito. Il percorso precedente resta intatto.',
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
    final key = definition;
    final node = key?.current(selections);
    final steps = key?.trail(selections) ?? [];
    final uncertain = node != null && selections[node.id] == 'unknown';
    final candidates = node == null ? <int>{} : key!.candidates(node.id);
    final dirty = !mapEquals(saved, selections);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          key?.title ??
              (widget.general
                  ? 'Chiave generale ITALIC'
                  : 'Physcia · bivi ricostruiti'),
        ),
        actions: [
          IconButton(
            key: const ValueKey('reconstructed-undo'),
            tooltip: 'Annulla ultima modifica',
            onPressed: saving || history.isEmpty
                ? null
                : () {
                    setState(() {
                      selections = history.removeLast();
                      revision++;
                    });
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _focusCouplet(),
                    );
                  },
            icon: const Icon(Icons.undo),
          ),
        ],
        bottom: key == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(42),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Row(
                    children: [
                      Icon(
                        Icons.eco_outlined,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${candidates.length} ${key.general ? (candidates.length == 1 ? "taxon nel ramo" : "taxa nel ramo") : (candidates.length == 1 ? "taxon da verificare" : "taxa possibili")}${key.unresolved(node!.id).isEmpty ? "" : " · ${key.unresolved(node.id).length} rami da approfondire"}',
                          key: const ValueKey('reconstructed-count'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
      bottomNavigationBar: key == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('reconstructed-back'),
                      onPressed: saving ? null : _back,
                      icon: const Icon(Icons.arrow_back),
                      label: Text(
                        steps.isEmpty && !uncertain
                            ? (key.general
                                  ? 'Indietro · caratteri iniziali'
                                  : 'Indietro · scelta del percorso')
                            : 'Indietro · bivio precedente',
                      ),
                    ),
                    if (widget.observation != null) ...[
                      Text(
                        !dirty
                            ? 'Nessuna modifica da salvare.'
                            : widget.observation!.identificationPath != null
                            ? 'Al salvataggio sostituirai l’ultimo percorso dell’osservazione.'
                            : 'Risposte non ancora salvate.',
                      ),
                      FilledButton.icon(
                        key: const ValueKey('reconstructed-save'),
                        onPressed: saving || !dirty ? null : _save,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(
                          selections.isEmpty
                              ? 'Rimuovi percorso salvato'
                              : 'Salva percorso nell’osservazione',
                        ),
                      ),
                    ],
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
              ExpansionTile(
                title: const Text('Informazioni sulla chiave'),
                children: [
                  Text(
                    widget.general || key?.general == true
                        ? (key?.scopeGenus == null
                              ? 'Segui i bivi della chiave generale. Alcuni richiedono reagenti o microscopio.'
                              : 'Gruppo selezionato: ${key!.scopeGenus}. La chiave è ridotta ai taxa documentati del genere già riconosciuto.')
                        : 'Percorso per il genere Physcia già riconosciuto. Alcuni bivi richiedono reagenti o microscopio.',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.general || key?.general == true
                        ? 'Le alternative conservano il testo inglese della fonte. I richiami ai termini aiutano a consultare il dizionario e non assegnano valori alla matrice.'
                        : 'Sintesi italiana da ITALIC: le condizioni dei rami sono da verificare e non confermano automaticamente la matrice.',
                  ),
                ],
              ),
              if (failed) ...[
                const Text('Impossibile caricare i bivi.'),
                TextButton(onPressed: _load, child: const Text('Riprova')),
              ] else if (key == null || node == null)
                const Center(child: CircularProgressIndicator())
              else ...[
                const SizedBox(height: 16),
                ExpansionTile(
                  title: const Text('Gruppo e filtri iniziali'),
                  children: [
                    if (key.preFilters.isNotEmpty)
                      Text(
                        'Caratteri iniziali: ${KeyPrefilter.summary(key.preFilters)}',
                      ),
                    Text(
                      '${key.coveredLocal} taxa locali · ${key.couplets} bivi · ${key.occurrences} percorsi terminali',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (key.general)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          '${key.unrepresented.length} taxa locali senza percorso in questo gruppo. ${key.extraTaxa.length} taxa aggiuntivi della fonte sono distinti dalla checklist. ${key.unresolved(key.root).length} rami portano a gruppi o continuazioni da approfondire.',
                        ),
                      ),
                    if (key.unavailableRecords.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Copertura: 22 taxa. Un riferimento storico a un percorso aggiuntivo non è disponibile; confronta la fonte online in caso di dubbio.',
                        ),
                      ),
                  ],
                ),
                if (!node.terminal)
                  TextButton.icon(
                    onPressed: _showCandidates,
                    icon: const Icon(Icons.format_list_bulleted),
                    label: const Text('Vedi le specie rimaste'),
                  ),
                SizedBox(key: coupletAnchor, height: 1),
                if (node.terminal && node.taxonId == null) ...[
                  const Text('Esito da approfondire nella fonte'),
                  Text(
                    node.unresolvedLabel!,
                    key: const ValueKey('reconstructed-unresolved'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const Text(
                    'Questo ramo non fornisce un nome di specie utilizzabile: consulta la chiave originale.',
                  ),
                ] else if (node.terminal) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Esito del percorso · verifica la specie sul campione',
                  ),
                  if (key.extraTaxa.contains(node.taxonId))
                    const Text(
                      'Taxon della fonte esterno alla checklist locale.',
                    ),
                  Text(
                    key.taxa[node.taxonId]!.scientificName,
                    key: const ValueKey('reconstructed-result'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  if (!key.extraTaxa.contains(node.taxonId) &&
                      widget.observation != null)
                    CandidateSelectionButton(
                      taxon: key.taxa[node.taxonId]!,
                      observation: widget.observation!,
                      store: widget.store!,
                      path: _candidatePath,
                      disabled: saving,
                      onBusy: _candidateBusy,
                      onSaved: _candidateSaved,
                    ),
                  if (!key.extraTaxa.contains(node.taxonId))
                    TextButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ItalicTaxonPage(taxon: key.taxa[node.taxonId]!),
                        ),
                      ),
                      icon: const Icon(Icons.menu_book_outlined),
                      label: const Text('Apri scheda della specie'),
                    ),
                ] else if (uncertain) ...[
                  const Text(
                    'Bivio non verificato: entrambe le alternative restano possibili. Consulta le specie rimaste oppure torna al bivio.',
                  ),
                  TextButton(
                    key: const ValueKey('reconstructed-reconsider'),
                    onPressed: saving ? null : () => _edit(node.id),
                    child: const Text('Torna al bivio'),
                  ),
                ] else ...[
                  Text(
                    'Bivio ${steps.length + 1} del tuo percorso',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  for (final (choiceIndex, choice) in node.choices.indexed)
                    Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                        side: BorderSide(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: .18),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.primary,
                                  child: Text(
                                    String.fromCharCode(65 + choiceIndex),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Alternativa ${String.fromCharCode(65 + choiceIndex)}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelLarge,
                                  ),
                                ),
                                Chip(
                                  visualDensity: VisualDensity.compact,
                                  label: Text(
                                    '${key.candidates(choice.target).length} taxa',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              choice.label,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    height: 1.4,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            if (choice.note.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(choice.note),
                              ),
                            if (choice.bindings.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  'Caratteri collegati: ${_bindings(choice)}',
                                ),
                              ),
                            if (key.general && choice.terms.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  'Termini del bivio: ${choice.terms.join(" · ")}',
                                ),
                              ),
                            const SizedBox(height: 10),
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.primary,
                                foregroundColor: Colors.white,
                                side: BorderSide.none,
                                minimumSize: const Size.fromHeight(48),
                              ),
                              key: ValueKey(
                                'reconstructed-choice-${choice.target}',
                              ),
                              onPressed: saving
                                  ? null
                                  : () => _change({
                                      ...selections,
                                      node.id: choice.target,
                                    }),
                              child: Text(
                                'Segui questa alternativa · ${key.candidates(choice.target).length} ${key.candidates(choice.target).length == 1 ? "taxon" : "taxa"}${key.unresolved(choice.target).isEmpty ? "" : " + rami da approfondire"}',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  TextButton(
                    key: const ValueKey('reconstructed-unknown'),
                    onPressed: saving
                        ? null
                        : () => _change({...selections, node.id: 'unknown'}),
                    child: const Text(
                      'Non so · mantieni entrambe le alternative',
                    ),
                  ),
                ],
                Link(
                  uri: key.sourceFor(
                    node.terminal && steps.isNotEmpty ? steps.last.node : node,
                  ),
                  target: LinkTarget.blank,
                  builder: (context, follow) => TextButton.icon(
                    onPressed: follow,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Confronta questo bivio in ITALIC'),
                  ),
                ),
                if (key.general)
                  TextButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CharacterDictionaryPage(),
                      ),
                    ),
                    icon: const Icon(Icons.menu_book_outlined),
                    label: const Text('Apri dizionario dei caratteri'),
                  ),
                if (steps.isNotEmpty)
                  ExpansionTile(
                    key: ValueKey('reconstructed-history-$revision'),
                    title: Text(
                      'Il tuo percorso (${steps.length} ${steps.length == 1 ? "scelta" : "scelte"})',
                    ),
                    children: [
                      for (final step in steps)
                        ListTile(
                          title: Text(step.choice.label),
                          subtitle: step.choice.bindings.isEmpty
                              ? null
                              : Text(_bindings(step.choice)),
                          trailing: TextButton(
                            onPressed: saving
                                ? null
                                : () => _edit(step.node.id),
                            child: const Text('Modifica'),
                          ),
                        ),
                    ],
                  ),
                if (selections.isNotEmpty)
                  TextButton.icon(
                    onPressed: saving ? null : () => _change({}),
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Ricomincia'),
                  ),
                if (!node.terminal)
                  RemainingCandidates(
                    key: candidatesAnchor,
                    scope: node.id,
                    taxa: [for (final id in candidates) key.taxa[id]!],
                    observation: widget.observation,
                    store: widget.store,
                    path: _candidatePath,
                    disabled: saving,
                    onBusy: _candidateBusy,
                    onSaved: _candidateSaved,
                    externalIds: key.extraTaxa,
                  ),
                if (!node.terminal)
                  for (final unresolved in key.unresolved(node.id))
                    ListTile(
                      title: Text(key.nodes[unresolved]!.unresolvedLabel!),
                      subtitle: const Text('Ramo da approfondire nella fonte'),
                    ),
                const Divider(height: 30),
                Text(key.citation),
                Text(
                  key.general
                      ? 'Fonte consultata il 2 novembre 2026. Le condizioni dei rami, incluse alternative e variazioni, restano separate dalle revisioni dei caratteri.'
                      : 'Fonte consultata il 2 novembre 2026. Le reazioni K qui riguardano la medulla, come nei bivi originali; sono distinte dai campi K dell’API dei traits.',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _bindings(ReconstructedChoice choice) => choice.bindings.entries
      .map((e) {
        final c = PhysciaPilot.character(e.key)!;
        return '${c.label}: ${c.labelFor(e.value)}';
      })
      .join(' · ');
}
