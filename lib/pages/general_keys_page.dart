import 'package:flutter/material.dart';
import 'package:url_launcher/link.dart';
import '../app_store.dart';
import '../data/character_matrix_repository.dart';
import '../data/italic_api_traits_repository.dart';
import '../services/key_prefilter.dart';
import '../widgets/offline_card.dart';
import '../models/observation.dart';
import '../services/reconstructed_key.dart';
import '../widgets/official_key_link.dart';
import 'italic_taxon_page.dart';
import 'reconstructed_key_page.dart';

class GeneralKeysPage extends StatefulWidget {
  const GeneralKeysPage({
    super.key,
    this.definition,
    this.matrix,
    this.apiMatrix,
    this.observation,
    this.store,
  }) : assert((observation == null) == (store == null));
  final ReconstructedKey? definition;
  final CharacterMatrix? matrix;
  final ApiTraitsMatrix? apiMatrix;
  final Observation? observation;
  final AppStore? store;
  @override
  State<GeneralKeysPage> createState() => _GeneralKeysPageState();
}

class _GeneralKeysPageState extends State<GeneralKeysPage> {
  ReconstructedKey? definition;
  CharacterMatrix? matrix;
  ApiTraitsMatrix? apiMatrix;
  final filters = <String, String>{};
  bool failed = false, missingOnly = false;
  final search = TextEditingController();
  String? genus;
  int visible = 20, revision = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => failed = false);
    try {
      final value = widget.definition ?? await ReconstructedKey.loadGeneral();
      final loadedMatrix =
          widget.matrix ?? await CharacterMatrixRepository().load();
      final loadedApi =
          widget.apiMatrix ?? await ItalicApiTraitsRepository().load();
      if (mounted) {
        setState(() {
          apiMatrix = loadedApi;
          definition = value;
          matrix = loadedMatrix;
        });
      }
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  Future<void> _start() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReconstructedKeyPage(
          definition: definition,
          general: true,
          genus: genus,
          startFresh: true,
          preFilters: Map.of(filters),
          matrix: matrix,
          apiMatrix: apiMatrix,
          observation: widget.observation,
          store: widget.store,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  void _setFilter(String id, String? value) => setState(() {
    if (value == null || value.isEmpty) {
      filters.remove(id);
    } else {
      filters[id] = value;
    }
  });

  String _groupSummary(String group) => KeyPrefilter.binaryCharacters
      .where((c) => c.group == group && filters.containsKey('binary:${c.id}'))
      .map(
        (c) => '${c.label}: ${filters['binary:${c.id}'] == '1' ? 'sì' : 'no'}',
      )
      .join(' · ');

  IconData _groupIcon(String group) => switch (group) {
    'Tallo' => Icons.eco_outlined,
    'Fotobionte' => Icons.grain,
    'Ascocarpi' => Icons.circle_outlined,
    'Apoteci' => Icons.filter_vintage_outlined,
    'Ascospore' => Icons.scatter_plot_outlined,
    'Reazione K' => Icons.science_outlined,
    _ => Icons.bubble_chart_outlined,
  };

  Widget _choiceRow(
    String id,
    String title,
    Map<String, String> options, {
    bool types = false,
  }) {
    final selected = types
        ? options.keys.where((k) => filters['binary:$k'] == '1').firstOrNull
        : filters[id];
    void choose(String? value) {
      if (!types) {
        _setFilter(id, value);
        return;
      }
      setState(() {
        for (final key in options.keys) {
          filters.remove('binary:$key');
        }
        if (value != null) {
          filters['binary:$value'] = '1';
        }
      });
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(title, style: Theme.of(context).textTheme.titleSmall),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                key: ValueKey('prefilter-$id-unknown'),
                label: const Text('Non so'),
                selected: selected == null,
                onSelected: (_) => choose(null),
              ),
              for (final option in options.entries)
                ChoiceChip(
                  key: ValueKey(
                    types
                        ? 'prefilter-binary:${option.key}'
                        : 'prefilter-$id-${option.key}',
                  ),
                  label: Text(option.value),
                  selected: selected == option.key,
                  onSelected: (value) => choose(value ? option.key : null),
                ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _groupChoices(String group) => switch (group) {
    'Tallo' => [
      _choiceRow('thallus', 'Tipo di tallo', const {
        'growth_form_fruticose': 'Fruticoso',
        'growth_form_foliose': 'Foglioso',
        'growth_form_squamulose': 'Squamuloso',
        'growth_form_leprose': 'Leproso',
        'growth_form_crustose': 'Crostoso',
        'growth_form_lichenicolous': 'Lichenicolo',
      }, types: true),
    ],
    'Fotobionte' => [
      _choiceRow('photobiont-type', 'Tipo di fotobionte', const {
        'photobiont_cyanobacterial': 'Cianobatteri',
        'photobiont_trentepohlioid': 'Trentepohlia',
        'photobiont_chlorococcoid': 'Alghe verdi clorococcoidi',
        'photobiont_absent': 'Assente',
      }, types: true),
    ],
    'Ascocarpi' => [
      _choiceRow('binary:ascocarps_present', 'Presenza', const {
        '1': 'Presenti',
        '0': 'Assenti',
      }),
      _choiceRow('ascocarp-form', 'Forma', const {
        'ascocarps_perithecioid': 'Peritecioidi',
        'ascocarps_apothecioid': 'Apotecioidi',
      }, types: true),
    ],
    'Apoteci' => [
      _choiceRow('binary:apothecia_lecanorine', 'Margine tallino', const {
        '1': 'Lecanorini',
        '0': 'Non lecanorini',
      }),
      _choiceRow('binary:apothecia_lirelliform', 'Forma lirelliforme', const {
        '1': 'Lirelliformi',
        '0': 'Non lirelliformi',
      }),
    ],
    'Ascospore' => [
      _choiceRow('spore-colour', 'Colore', const {
        'ascospores_pigmented': 'Pigmentate',
        'ascospores_hyaline': 'Ialine',
      }, types: true),
      _choiceRow('spore-cells', 'Numero di cellule', const {
        'ascospores_1-celled': 'Una cellula',
        'ascospores_2-celled': 'Due cellule',
        'ascospores_more_than_2-celled': 'Più di due cellule',
      }, types: true),
      _choiceRow('spore-form', 'Struttura', const {
        'ascospores_polarilocular': 'Polariloculari',
        'ascospores_muriform_or_submuriform': 'Muriformi / submuriformi',
      }, types: true),
      _choiceRow('spores-per-ascus', 'Spore per asco', const {
        'ascospores_less_than_8_per_ascus': 'Meno di 8',
        'ascospores_8_per_ascus': '8',
        'ascospores_more_than_8_per_ascus': 'Più di 8',
      }, types: true),
    ],
    'Reazione K' => [
      _choiceRow('cortex-reaction', 'Reazione della corteccia', const {
        'cortex_k_negative': 'K−',
        'cortex_k_yellow_to_orange': 'Giallo / arancio',
        'cortex_k_red': 'Rosso',
        'cortex_k_yellow_turning_to_red': 'Giallo → rosso',
      }, types: true),
    ],
    _ => [
      const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Text(
          'Comprende le strutture simili indicate dalla fonte. I valori non documentati restano sconosciuti.',
        ),
      ),
      _choiceRow(
        'binary:reproduction_soredia_or_similar',
        'Soredi o strutture simili',
        const {'1': 'Presenti', '0': 'Assenti'},
      ),
      _choiceRow(
        'binary:reproduction_isidia_or_similar',
        'Isidi o strutture simili',
        const {'1': 'Presenti', '0': 'Assenti'},
      ),
    ],
  };

  @override
  Widget build(BuildContext context) {
    final key = definition;
    final query = search.text.trim().toLowerCase();
    final catalog =
        key?.catalog.values
            .where(
              (t) =>
                  (genus == null ||
                      t.scientificName.split(' ').first == genus) &&
                  (!missingOnly || key.unrepresented.containsKey(t.italicId)) &&
                  (query.isEmpty ||
                      t.italicId.toString() == query ||
                      t.scientificName.toLowerCase().contains(query) ||
                      t.synonyms.any((s) => s.toLowerCase().contains(query))),
            )
            .toList()
          ?..sort((a, b) => a.scientificName.compareTo(b.scientificName));
    final showList = query.isNotEmpty || missingOnly || genus != null;
    final genusCovered =
        key?.taxa.values
            .where(
              (t) =>
                  !key.extraTaxa.contains(t.italicId) &&
                  (genus == null || t.scientificName.split(' ').first == genus),
            )
            .length ??
        0;
    final scoped = key == null || genus == null || genusCovered == 0
        ? key
        : key.forGenus(genus!);
    final comparison = scoped == null || matrix == null
        ? null
        : KeyPrefilter(scoped, matrix!, filters, apiMatrix: apiMatrix);
    return Scaffold(
      appBar: AppBar(title: const Text('Chiavi · tutti i taxa')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Inizia dai caratteri del campione, oppure cerca una specie per studiare tutti i suoi percorsi nella chiave.',
              ),
              if (failed) ...[
                const Text('Impossibile caricare la chiave generale.'),
                TextButton(onPressed: _load, child: const Text('Riprova')),
              ] else if (key == null)
                const Center(child: CircularProgressIndicator())
              else ...[
                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${key.coveredLocal} su ${key.catalog.length} taxa locali con percorso',
                          key: const ValueKey('general-coverage'),
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        Text(
                          '${key.unrepresented.length} taxa senza percorso nell’albero scaricato. La ricerca comprende tutta la checklist.',
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${key.couplets} bivi e ${key.occurrences} percorsi della fonte. Sono conservati anche ${key.extraTaxa.length} taxa esterni alla checklist e ${key.unresolved(key.root).length} esiti da approfondire.',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Le alternative della chiave generale mantengono il testo originale inglese, con richiami ai termini del dizionario. Il pilota Physcia è disponibile anche in italiano.',
                ),
                const SizedBox(height: 16),
                if (genus == null)
                  Autocomplete<String>(
                    key: ValueKey('general-genus-$revision'),
                    optionsBuilder: (v) => v.text.trim().isEmpty
                        ? const Iterable<String>.empty()
                        : key.genera.where(
                            (g) => g.toLowerCase().startsWith(
                              v.text.trim().toLowerCase(),
                            ),
                          ),
                    onSelected: (g) => setState(() {
                      genus = g;
                      visible = 20;
                    }),
                    fieldViewBuilder:
                        (context, controller, focus, onSubmitted) => TextField(
                          key: const ValueKey('general-genus-input'),
                          controller: controller,
                          focusNode: focus,
                          decoration: const InputDecoration(
                            labelText: 'Genere già riconosciuto (facoltativo)',
                            hintText: 'Seleziona un nome dai suggerimenti',
                            border: OutlineInputBorder(),
                          ),
                        ),
                  )
                else
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      Chip(label: Text('Genere: $genus')),
                      TextButton(
                        onPressed: () => setState(() {
                          genus = null;
                          visible = 20;
                          revision++;
                        }),
                        child: const Text('Tutti i generi'),
                      ),
                    ],
                  ),
                const SizedBox(height: 16),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Caratteri del campione',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Scegli solo i caratteri che riconosci. Non so lascia aperte le possibilità; i dati mancanti o in conflitto mantengono la specie tra i candidati.',
                        ),
                        const SizedBox(height: 16),
                        ExpansionTile(
                          key: const ValueKey('prefilter-substrate-group'),
                          tilePadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.landscape_outlined,
                            size: 22,
                          ),
                          title: const Text('Substrato'),
                          subtitle: filters['substrata'] == null
                              ? null
                              : Text(
                                  KeyPrefilter.legacyQuestions
                                      .firstWhere((q) => q.id == 'substrata')
                                      .label(filters['substrata']!),
                                ),
                          children: [
                            for (final q in KeyPrefilter.legacyQuestions.where(
                              (q) => q.id == 'substrata',
                            ))
                              _choiceRow('substrata', '', {
                                for (final c in q.choices) c.id: c.label,
                              }),
                          ],
                        ),
                        for (final group
                            in KeyPrefilter.binaryCharacters
                                .map((c) => c.group)
                                .toSet())
                          ExpansionTile(
                            key: ValueKey('binary-group-$group'),
                            tilePadding: EdgeInsets.zero,
                            childrenPadding: const EdgeInsets.only(bottom: 10),
                            leading: Icon(_groupIcon(group), size: 22),
                            title: Text(group),
                            subtitle: _groupSummary(group).isEmpty
                                ? null
                                : Text(_groupSummary(group)),
                            children: _groupChoices(group),
                          ),
                        const Divider(height: 24),
                        if (comparison != null)
                          Text(
                            '${comparison.coveredLocal} taxa locali con percorso${filters.isEmpty ? "" : " dopo il confronto"} · ${comparison.uncertain.where((id) => !key.extraTaxa.contains(id) && !key.unrepresented.containsKey(id)).length} mantenuti per dati incompleti.',
                            key: const ValueKey('prefilter-count'),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        if (filters.isNotEmpty)
                          TextButton.icon(
                            onPressed: () => setState(filters.clear),
                            icon: const Icon(Icons.restart_alt),
                            label: const Text('Azzera caratteri del campione'),
                          ),
                        if (genusCovered == 0 || comparison?.coveredLocal == 0)
                          const Text(
                            'Nessun taxon locale con percorso per questa selezione. Modifica o azzera i caratteri.',
                          ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            key: const ValueKey('general-start'),
                            onPressed:
                                genusCovered == 0 ||
                                    comparison?.coveredLocal == 0
                                ? null
                                : _start,
                            icon: const Icon(Icons.account_tree_outlined),
                            label: Text(
                              genus == null
                                  ? 'Inizia la chiave'
                                  : 'Inizia la chiave di $genus',
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'I caratteri scelti filtrano le specie e i bivi della chiave. Gli esiti da approfondire della fonte restano disponibili.',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const OfflineCard(),
                const Divider(height: 30),
                Text(
                  'Studia i percorsi di una specie',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const ValueKey('general-species-search'),
                  controller: search,
                  decoration: InputDecoration(
                    labelText: 'Nome, sinonimo oppure ID ITALIC',
                    border: const OutlineInputBorder(),
                    suffixIcon: search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Cancella ricerca',
                            onPressed: () {
                              search.clear();
                              setState(() => visible = 20);
                            },
                            icon: const Icon(Icons.clear),
                          ),
                  ),
                  onChanged: (_) => setState(() => visible = 20),
                ),
                SwitchListTile(
                  key: const ValueKey('general-missing-only'),
                  contentPadding: EdgeInsets.zero,
                  value: missingOnly,
                  title: const Text('Mostra i taxa senza percorso disponibile'),
                  onChanged: (v) => setState(() {
                    missingOnly = v;
                    visible = 20;
                  }),
                ),
                if (!showList)
                  const Text(
                    'Cerca una specie per vedere i caratteri di ciascun percorso. Alcune specie compaiono in più rami.',
                  )
                else ...[
                  Text(
                    '${catalog!.length} ${catalog.length == 1 ? "taxon trovato" : "taxa trovati"}',
                    key: const ValueKey('general-search-count'),
                  ),
                  for (final t in catalog.take(visible))
                    Card(
                      child: ListTile(
                        key: ValueKey('general-taxon-${t.italicId}'),
                        title: Text(
                          t.scientificName,
                          style: const TextStyle(fontStyle: FontStyle.italic),
                        ),
                        subtitle: Text(
                          key.unrepresented.containsKey(t.italicId)
                              ? 'Percorso non disponibile · consulta scheda e chiavi associate'
                              : '${key.pathCountFor(t.italicId!)} ${key.pathCountFor(t.italicId!) == 1 ? "percorso nella fonte" : "percorsi nella fonte"}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => GeneralTaxonPathsPage(
                              definition: key,
                              taxonId: t.italicId!,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (catalog.length > visible)
                    TextButton(
                      onPressed: () => setState(() => visible += 20),
                      child: const Text('Mostra altri taxa'),
                    ),
                ],
                const Divider(height: 28),
                Text(key.citation),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class GeneralTaxonPathsPage extends StatelessWidget {
  const GeneralTaxonPathsPage({
    super.key,
    required this.definition,
    required this.taxonId,
  });
  final ReconstructedKey definition;
  final int taxonId;
  @override
  Widget build(BuildContext context) {
    final taxon = definition.catalog[taxonId]!;
    final paths = definition.pathsFor(taxonId);
    final associated = definition.associatedKeys[taxonId] ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('Percorsi della specie')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                taxon.scientificName,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 10),
              if (paths.isEmpty) ...[
                const Text(
                  'Questo taxon non ha un percorso nell’albero generale scaricato. I dati della scheda restano disponibili.',
                ),
                if (associated.isEmpty)
                  const Text(
                    'Nel controllo del 2 novembre 2026, l’API non ha restituito chiavi associate per questo ID.',
                  )
                else ...[
                  const Text('Chiavi associate restituite da ITALIC:'),
                  for (final link in associated)
                    Link(
                      uri: link.url,
                      target: LinkTarget.blank,
                      builder: (context, follow) => TextButton.icon(
                        onPressed: follow,
                        icon: const Icon(Icons.open_in_new),
                        label: Text(link.title),
                      ),
                    ),
                ],
                const SizedBox(height: 10),
                const Text(
                  'Le eventuali chiavi del genere possono avere un ambito diverso: controlla i taxa inclusi.',
                ),
                GenusKeyLinks(genus: taxon.scientificName.split(' ').first),
              ] else ...[
                Text(
                  '${paths.length} ${paths.length == 1 ? "percorso disponibile" : "percorsi disponibili"}',
                  key: const ValueKey('taxon-path-count'),
                ),
                const Text(
                  'Sono sequenze della chiave da studiare e verificare sul campione. Le alternative e il contesto restano separati; non sono conferme automatiche della matrice.',
                ),
                for (var i = 0; i < paths.length; i++)
                  ExpansionTile(
                    key: ValueKey('taxon-path-$i'),
                    initiallyExpanded: paths.length == 1,
                    title: Text(
                      'Percorso ${i + 1} · ${paths[i].length} scelte',
                    ),
                    children: [
                      for (var j = 0; j < paths[i].length; j++)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Text('${j + 1}'),
                          title: Text(paths[i][j].choice.label),
                          subtitle: paths[i][j].choice.terms.isEmpty
                              ? null
                              : Text(
                                  'Termini: ${paths[i][j].choice.terms.join(" · ")}',
                                ),
                          trailing: Link(
                            uri: definition.sourceFor(paths[i][j].node),
                            target: LinkTarget.blank,
                            builder: (context, follow) => IconButton(
                              onPressed: follow,
                              tooltip: 'Vedi il bivio originale',
                              icon: const Icon(Icons.open_in_new),
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ItalicTaxonPage(taxon: taxon),
                  ),
                ),
                icon: const Icon(Icons.menu_book_outlined),
                label: const Text('Apri scheda della specie'),
              ),
              const Divider(height: 28),
              Text(definition.citation),
            ],
          ),
        ),
      ),
    );
  }
}
