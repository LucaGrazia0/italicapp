import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/italic_api_traits_repository.dart';

class ItalicApiTraitsPage extends StatefulWidget {
  const ItalicApiTraitsPage({super.key, this.matrix});
  final ApiTraitsMatrix? matrix;
  @override
  State<ItalicApiTraitsPage> createState() => _ItalicApiTraitsPageState();
}

class _ItalicApiTraitsPageState extends State<ItalicApiTraitsPage> {
  ApiTraitsMatrix? matrix;
  bool failed = false, onlyComparisons = false;
  String group = 'Tallo';
  int page = 0;
  static const pageSize = 20;
  final search = TextEditingController();
  final horizontal = ScrollController(), vertical = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => failed = false);
    try {
      final loaded = widget.matrix ?? await ItalicApiTraitsRepository().load();
      if (mounted) setState(() => matrix = loaded);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  void dispose() {
    search.dispose();
    horizontal.dispose();
    vertical.dispose();
    super.dispose();
  }

  void _resetScroll() {
    if (vertical.hasClients) vertical.jumpTo(0);
    if (horizontal.hasClients) horizontal.jumpTo(0);
  }

  Future<void> _detail(ApiTraitRow row, ApiTraitCharacter character) async {
    final value = row.values[character.id];
    final reproduction = character.isReproduction;
    final evidence = row.reproductionEvidence ?? const <String, dynamic>{};
    final sourceUrl = reproduction
        ? (evidence['sourceUrl'] as String? ?? '')
        : row.sourceUrl;
    final sourceDate = reproduction
        ? (evidence['snapshotImportedAt'] as String? ?? '')
        : row.retrievedAt;
    final concerns = row.conflicts.where((c) => c.concerns(character.id));
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(character.label),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(row.taxon.scientificName),
              const SizedBox(height: 12),
              Text(
                value == null
                    ? (reproduction
                          ? 'Indicazione non documentata per questa categoria. Non significa assenza della struttura.'
                          : 'Dato non disponibile.')
                    : (reproduction
                          ? 'Indicazione documentata nella strategia riproduttiva.'
                          : 'Valore API: $value · ${value == 1 ? 'stato selezionato' : 'stato non selezionato'}.'),
              ),
              const SizedBox(height: 8),
              Text(
                reproduction
                    ? 'Fonte: checklist ITALIC locale, dati ecologici strutturati. La categoria comprende anche strutture simili: non conferma da sola soredi veri o isidi veri. Una strategia prevalentemente sessuale non ne dimostra l’assenza.'
                    : 'Dato trascritto dall’API · da verificare. Lo zero riguarda questo stato specifico; non dimostra da solo l’assenza dell’intera struttura.',
              ),
              if (reproduction) ...[
                const SizedBox(height: 12),
                SelectableText(
                  (evidence['quote'] as String? ?? '').isEmpty
                      ? 'Strategia riproduttiva non disponibile nella fonte.'
                      : 'Strategia nella fonte: “${evidence['quote']}”',
                ),
                if ((evidence['code'] as String? ?? '').isNotEmpty)
                  Text('Codice della fonte: ${evidence['code']}'),
                if (row.reproductionChanged)
                  const Text(
                    'La fonte locale è cambiata: indicazione sospesa fino all’aggiornamento della matrice.',
                  ),
              ],
              for (final concern in concerns) ...[
                const SizedBox(height: 12),
                Text(
                  'Da confrontare · ${concern.label}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                SelectableText('Descrizione locale: “${concern.quote}”'),
                const Text(
                  'Il valore API differisce dal testo. Il valore originale è conservato.',
                ),
              ],
              if (!reproduction && row.warning.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Avviso della fonte: ${row.warning}'),
              ],
              if (!reproduction && row.schemaIssueCount > 0) ...[
                const SizedBox(height: 12),
                const Text(
                  'La risposta contiene campi nuovi o valori non interpretabili. I dati mancanti restano indicati con ?.',
                ),
              ],
              const SizedBox(height: 12),
              if (sourceDate.length >= 10)
                Text(
                  '${reproduction ? 'Ecologia locale importata' : 'Acquisito'}: ${sourceDate.substring(0, 10)}',
                ),
              SelectableText(
                'Campo originale: ${reproduction ? evidence['field'] : character.id}\n$sourceUrl',
              ),
              if (!reproduction && row.descriptionChanged) ...[
                const SizedBox(height: 12),
                const Text(
                  'La descrizione locale è cambiata rispetto al confronto salvato. Il confronto va aggiornato.',
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                final opened = await launchUrl(
                  Uri.parse(sourceUrl),
                  mode: LaunchMode.externalApplication,
                );
                if (!opened) throw StateError('Unable to open source');
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Impossibile aprire la fonte. Il collegamento è riportato nei dettagli.',
                      ),
                    ),
                  );
                }
              }
            },
            child: Text(reproduction ? 'Fonte ITALIC' : 'Fonte API'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Chiudi'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Matrice · ITALIC API'),
      actions: [
        IconButton(
          tooltip: 'Come leggere i dati API',
          icon: const Icon(Icons.info_outline),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Dati della fonte ITALIC'),
              content: const SingleChildScrollView(
                child: Text(
                  'La matrice unisce 29 stati dell’API e due indicazioni della strategia riproduttiva nella checklist locale.\n\n'
                  'Riproduzione: 1 indica soredi o strutture simili, oppure isidi o strutture simili, secondo la strategia documentata. Negli altri casi resta ?, senza dedurre assenze o la presenza di soredi veri e isidi veri. Le due categorie comprendono anche blastidi e schizidi.\n\n'
                  'Lo zero dei campi API non descrive da solo l’assenza di un organo e non va esteso ad altri caratteri.\n\n'
                  'Il confronto automatico con le descrizioni controlla il numero di spore per asco e alcuni casi di reazione K. L’assenza di segnalazioni non certifica la concordanza di tutti i caratteri.\n\n'
                  'Le citazioni mostrate provengono dalla descrizione locale. I valori API sono conservati nella forma originale e non approvati automaticamente per la chiave. Le revisioni salvate dall’autore restano nella matrice di revisione.',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Chiudi'),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
    body: failed
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Impossibile caricare la matrice API locale.'),
                TextButton(onPressed: _load, child: const Text('Riprova')),
              ],
            ),
          )
        : matrix == null
        ? const Center(child: CircularProgressIndicator())
        : _content(),
  );

  Widget _content() {
    final data = matrix!;
    final query = search.text.trim().toLowerCase();
    final rows = data.taxa
        .where(
          (r) =>
              (!onlyComparisons || r.needsComparison) &&
              (query.isEmpty ||
                  r.taxon.scientificName.toLowerCase().contains(query) ||
                  r.taxon.italicId.toString() == query ||
                  r.taxon.synonyms.any((s) => s.toLowerCase().contains(query))),
        )
        .toList();
    final characters = data.characters
        .where((c) => group == 'Tutti' || c.group == group)
        .toList();
    final start = page * pageSize;
    final shown = rows.skip(start).take(pageSize).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${data.taxa.length} taxa × ${data.characters.length} colonne · ${data.recordedCells} valori acquisiti',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(
                'API: ${data.populatedTaxa} taxa con valori · ${data.taxa.length - data.populatedTaxa} senza dati',
              ),
              const SizedBox(height: 6),
              const Text(
                '1 = stato documentato · 0 = stato non selezionato nell’API · ? = non documentato. Tocca una cella per fonte e dettagli.',
              ),
              const SizedBox(height: 6),
              Text(
                'Riproduzione: ${data.sorediaIndications} indicazioni di soredi o simili · ${data.isidiaIndications} di isidi o simili. Le revisioni personali restano nella matrice di revisione.',
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('api-matrix-search'),
                controller: search,
                decoration: InputDecoration(
                  labelText: 'Cerca specie, sinonimo o ID',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Cancella ricerca',
                          onPressed: () {
                            search.clear();
                            setState(() => page = 0);
                            _resetScroll();
                          },
                          icon: const Icon(Icons.clear),
                        ),
                ),
                onChanged: (_) {
                  setState(() => page = 0);
                  _resetScroll();
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: const ValueKey('api-matrix-group'),
                initialValue: group,
                decoration: const InputDecoration(labelText: 'Caratteri'),
                items: ['Tutti', ...data.characters.map((c) => c.group).toSet()]
                    .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => group = value);
                    _resetScroll();
                  }
                },
              ),
            ],
          ),
        ),
        CheckboxListTile(
          key: const ValueKey('api-matrix-comparisons'),
          dense: true,
          title: Text('Solo taxa con segnalazioni (${data.comparisonRows})'),
          value: onlyComparisons,
          onChanged: (value) {
            setState(() {
              onlyComparisons = value ?? false;
              page = 0;
            });
            _resetScroll();
          },
        ),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('Nessun taxon per questa ricerca.'))
              : Scrollbar(
                  controller: vertical,
                  child: SingleChildScrollView(
                    controller: vertical,
                    child: Scrollbar(
                      controller: horizontal,
                      thumbVisibility: true,
                      notificationPredicate: (notification) =>
                          notification.metrics.axis == Axis.horizontal,
                      child: SingleChildScrollView(
                        controller: horizontal,
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowHeight: 80,
                          columns: [
                            const DataColumn(label: Text('Taxon')),
                            for (final c in characters)
                              DataColumn(
                                tooltip: c.label,
                                label: SizedBox(
                                  width: 170,
                                  child: Text(
                                    c.label,
                                    softWrap: true,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                          ],
                          rows: [
                            for (final row in shown)
                              DataRow(
                                cells: [
                                  DataCell(
                                    SizedBox(
                                      width: 250,
                                      child: Text(
                                        '${row.taxon.scientificName}\nID ${row.taxon.italicId}${row.needsComparison ? ' · Da confrontare' : ''}',
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  for (final c in characters)
                                    DataCell(
                                      Semantics(
                                        button: true,
                                        label:
                                            '${row.taxon.scientificName}, ${c.label}: ${row.values[c.id] ?? '?'}',
                                        child: SizedBox(
                                          key: ValueKey(
                                            'api-cell-${row.taxon.italicId}-${c.id}',
                                          ),
                                          width: 140,
                                          child: Text(
                                            '${row.values[c.id] ?? '?'}${row.conflicts.any((f) => f.concerns(c.id)) ? ' ⚠' : ''}',
                                          ),
                                        ),
                                      ),
                                      onTap: () => _detail(row, c),
                                    ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    rows.isEmpty
                        ? '0 taxa'
                        : '${start + 1}–${start + shown.length} di ${rows.length} ${rows.length == 1 ? 'taxon' : 'taxa'}',
                  ),
                ),
                IconButton(
                  key: const ValueKey('api-matrix-previous'),
                  tooltip: 'Pagina precedente',
                  onPressed: page == 0
                      ? null
                      : () {
                          setState(() => page--);
                          _resetScroll();
                        },
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  key: const ValueKey('api-matrix-next'),
                  tooltip: 'Pagina successiva',
                  onPressed: start + pageSize >= rows.length
                      ? null
                      : () {
                          setState(() => page++);
                          _resetScroll();
                        },
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
