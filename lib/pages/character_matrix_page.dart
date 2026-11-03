import 'package:flutter/material.dart';
import '../data/character_matrix_repository.dart';
import 'italic_taxon_page.dart';
import 'structured_key_page.dart';
import 'physcia_review_page.dart';
import '../services/physcia_review_engine.dart';
import '../services/character_dictionary.dart';
import '../data/character_review_repository.dart';
import '../models/character_review.dart';
import '../services/reviewed_matrix.dart';
import 'character_review_page.dart';

class CharacterMatrixPage extends StatefulWidget {
  const CharacterMatrixPage({
    super.key,
    this.matrix,
    this.dictionary,
    this.repository,
    this.reviewRepository,
  });
  final CharacterMatrix? matrix;
  final CharacterDictionary? dictionary;
  final CharacterMatrixRepository? repository;
  final CharacterReviewRepository? reviewRepository;
  @override
  State<CharacterMatrixPage> createState() => _CharacterMatrixPageState();
}

class _CharacterMatrixPageState extends State<CharacterMatrixPage> {
  CharacterMatrix? matrix;
  CharacterMatrix? displayedMatrix;
  ReviewRegistry registry = ReviewRegistry([]);
  late final CharacterReviewRepository reviewRepository;
  bool reviewsFailed = false;
  bool loading = true, failed = false;
  final search = TextEditingController();
  final horizontal = ScrollController();
  final vertical = ScrollController();
  String group = 'Tutti';
  int page = 0;
  static const pageSize = 20;

  @override
  void initState() {
    super.initState();
    reviewRepository = widget.reviewRepository ?? CharacterReviewRepository();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      final loaded =
          matrix ??
          widget.matrix ??
          await (widget.repository ?? CharacterMatrixRepository()).load();
      try {
        registry = ReviewRegistry(await reviewRepository.all());
        reviewsFailed = false;
      } catch (_) {
        reviewsFailed = true;
      }
      if (mounted) {
        setState(() {
          matrix = loaded;
          displayedMatrix = reviewedMatrix(loaded, registry);
        });
      }
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _openReviews() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PhysciaReviewPage(
          dictionary: widget.dictionary,
          matrix: matrix,
          reviewRepository: reviewRepository,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _editCell(MatrixTaxon row, String id) async {
    final original = matrix!.taxa.firstWhere(
      (r) => r.taxon.italicId == row.taxon.italicId,
    );
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CharacterReviewPage(
          dictionary: widget.dictionary,
          row: original,
          character: PhysciaPilot.character(id)!,
          registry: registry,
          repository: reviewRepository,
        ),
      ),
    );
    if (mounted) await _load();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Matrice specie × caratteri'),
        actions: [
          IconButton(
            key: const ValueKey('matrix-review-physcia'),
            tooltip: 'Revisiona Physcia',
            onPressed: matrix == null || loading || failed
                ? null
                : _openReviews,
            icon: const Icon(Icons.fact_check_outlined),
          ),

          IconButton(
            key: const ValueKey('matrix-start-structured-key'),
            tooltip: 'Usa i 4 caratteri nelle chiavi',
            onPressed: matrix == null || loading || failed
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StructuredKeyPage(matrix: matrix),
                    ),
                  ),
            icon: const Icon(Icons.playlist_add_check),
          ),

          IconButton(
            tooltip: 'Come leggere la matrice',
            icon: const Icon(Icons.info_outline),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Come leggere la matrice'),
                content: const SingleChildScrollView(
                  child: Text(
                    'Ogni riga è un taxon della checklist, incluse le entità infraspecifiche. Tocca una cella per vedere il valore e le citazioni. Scorri in orizzontale per gli altri caratteri.\n\n'
                    'Non codificato: informazione mancante, non assenza del carattere.\n\n'
                    'Da chiarire: menzione, variabilità o valori discordanti nel testo.\n\n'
                    '* Da revisionare: estrazione automatica o codifica del pilota. Anche un valore registrato richiede controllo della citazione.\n\n'
                    'Modifiche salvate: il valore della tua ultima revisione compare nella cella con stato e autore. Anche le bozze sono conservate; solo i valori revisionati e stabili partecipano alla prova Physcia. Le revisioni restano in questo browser e indirizzo.\n\n'
                    'Le reazioni chimiche sono separate per compartimento. Il segno +/− non riassume colore, intensità o sequenza: leggi la citazione.\n\n'
                    'I dati strutturati restano distinti: una strategia riproduttiva prevalente non dimostra assenze di soredi o isidi. Solo questi quattro gruppi strutturati alimentano il percorso guidato. Le estrazioni da revisionare non vengono usate per selezionare i candidati.',
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
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : failed
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Impossibile caricare la matrice locale.'),
                  TextButton(onPressed: _load, child: const Text('Riprova')),
                ],
              ),
            )
          : _content(),
    );
  }

  Widget _content() {
    final data = displayedMatrix!;
    final query = search.text.trim().toLowerCase();
    final rows = data.taxa
        .where(
          (r) =>
              query.isEmpty ||
              r.taxon.scientificName.toLowerCase().contains(query) ||
              r.taxon.italicId.toString() == query ||
              r.taxon.synonyms.any((s) => s.toLowerCase().contains(query)),
        )
        .toList();
    final characters = data.characters
        .where((c) => group == 'Tutti' || c.group == group)
        .toList();
    final start = page * pageSize;
    final displayed = rows.skip(start).take(pageSize).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${data.taxa.length} taxa × ${data.characters.length} caratteri · ${data.availableCells} celle con evidenze',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              const Text(
                '* = proposta · Le tue modifiche mostrano stato e autore. Tocca una cella per i dettagli.',
              ),
              if (reviewsFailed)
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Revisioni locali non disponibili: la matrice potrebbe non mostrare tutte le tue modifiche.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      onPressed: _load,
                      tooltip: 'Ricarica revisioni',
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              if (data.staleCells > 0)
                Text(
                  '${data.staleCells} celle con fonte cambiata: valori sospesi.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 10),
              TextField(
                controller: search,
                key: const ValueKey('matrix-search'),
                onChanged: (_) {
                  setState(() => page = 0);
                  _resetScroll();
                },
                decoration: InputDecoration(
                  labelText: 'Cerca specie, genere, sinonimo o ID ITALIC',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: search.text.isEmpty
                      ? null
                      : IconButton(
                          key: const ValueKey('matrix-clear-search'),
                          tooltip: 'Cancella ricerca',
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            search.clear();
                            setState(() => page = 0);
                            _resetScroll();
                          },
                        ),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: const ValueKey('matrix-group'),
                initialValue: group,
                decoration: const InputDecoration(labelText: 'Caratteri'),
                items: ['Tutti', ...data.characters.map((c) => c.group).toSet()]
                    .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                    .toList(),
                onChanged: (value) {
                  setState(() => group = value!);
                  _resetScroll();
                },
              ),
            ],
          ),
        ),
        if (rows.isEmpty)
          const Expanded(
            child: Center(child: Text('Nessun taxon per questa ricerca.')),
          )
        else
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final nameWidth = constraints.maxWidth < 600 ? 150.0 : 260.0;
                return Scrollbar(
                  controller: horizontal,
                  thumbVisibility: true,
                  notificationPredicate: (n) =>
                      n.metrics.axis == Axis.horizontal,
                  child: Scrollbar(
                    controller: vertical,
                    child: SingleChildScrollView(
                      controller: vertical,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: nameWidth,
                            child: Column(
                              children: [
                                _box(
                                  width: nameWidth,
                                  height: 88,
                                  header: true,
                                  child: const Text(
                                    'Taxon ITALIC',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                for (final row in displayed)
                                  _box(
                                    width: nameWidth,
                                    child: InkWell(
                                      onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              ItalicTaxonPage(taxon: row.taxon),
                                        ),
                                      ),
                                      child: Tooltip(
                                        message: row.taxon.scientificName,
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              row.taxon.scientificName,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                            Text(
                                              'ID ${row.taxon.italicId}',
                                              style: Theme.of(
                                                context,
                                              ).textTheme.labelSmall,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              controller: horizontal,
                              scrollDirection: Axis.horizontal,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      for (final c in characters)
                                        _box(
                                          height: 88,
                                          header: true,
                                          child: Tooltip(
                                            message: c.description,
                                            child: Text(
                                              c.label,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  for (final row in displayed)
                                    Row(
                                      children: [
                                        for (final c in characters)
                                          _cell(row, c),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  key: const ValueKey('matrix-previous'),
                  tooltip: 'Pagina precedente',
                  onPressed: page == 0
                      ? null
                      : () {
                          setState(() => page--);
                          _resetScroll();
                        },
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    rows.isEmpty
                        ? '0 taxa'
                        : '${start + 1}–${start + displayed.length} di ${rows.length} ${rows.length == 1 ? "taxon" : "taxa"}',
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  key: const ValueKey('matrix-next'),
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

  Widget _box({
    required Widget child,
    double width = 160,
    double height = 80,
    bool header = false,
    Color? color,
  }) => Container(
    width: width,
    height: height,
    alignment: Alignment.centerLeft,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: color ?? (header ? const Color(0xFFEAF0E9) : Colors.white),
      border: Border.all(color: const Color(0xFFDCE5DB), width: .5),
    ),
    child: child,
  );

  Widget _cell(MatrixTaxon row, MatrixCharacter character) {
    final cell = row.cell(character.id);
    final record = cell.manualReview ?? cell.applicabilityReview;
    final label = cell.label(character);
    final suffix =
        record == null &&
            !cell.isUnknown &&
            !cell.isStructured &&
            !cell.isNotApplicable
        ? ' *'
        : '';
    return _box(
      color: cell.isNotApplicable
          ? const Color(0xFFF0F0F0)
          : record != null && !cell.stale
          ? const Color(0xFFEAF2FA)
          : cell.isUnknown
          ? null
          : cell.isStructured
          ? const Color(0xFFF4F8F3)
          : const Color(0xFFFFF8EA),
      child: InkWell(
        key: ValueKey('matrix-cell-${row.taxon.italicId}-${character.id}'),
        onTap: () => _showEvidence(row, character, cell),
        child: SizedBox.expand(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              record == null
                  ? '$label$suffix'
                  : '$label · ${record.statusLabel}\n${record.reviewer}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showEvidence(
    MatrixTaxon row,
    MatrixCharacter character,
    CharacterCell cell,
  ) => showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(character.label),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                row.taxon.scientificName,
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
              Text('ITALIC ID ${row.taxon.italicId}'),
              const SizedBox(height: 16),
              Text(
                cell.label(character),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                cell.isUnknown
                    ? cell.stale
                          ? 'La fonte è cambiata o la codifica non è più verificabile. Rigenera e revisiona questa cella.'
                          : 'Nessuna informazione codificata. Non equivale all’assenza del carattere.'
                    : cell.reviewLabel,
              ),
              const SizedBox(height: 8),
              if (cell.applicabilityReview case final absence?) ...[
                Text('Non applicabile: ${PhysciaPilot.absenceLabel(absence)}.'),
                Text(
                  'Fonte: cella ${PhysciaPilot.character(absence.characterId)!.label} · ${absence.statusLabel} · ${absence.reviewer} · versione ${absence.version}',
                ),
                Text(
                  'I valori precedenti rimangono nella cronologia. Modifica ${PhysciaPilot.character(absence.characterId)!.label} per riattivare questo campo.',
                ),
              ],
              if (cell.manualReview case final record?) ...[
                Text('Modifica salvata nella matrice · ${record.statusLabel}'),
                Text('Autore: ${record.reviewer} · versione ${record.version}'),
                Text(
                  'Salvata: ${record.createdAt.toLocal().toIso8601String()}',
                ),
                if (record.notes.isNotEmpty) Text('Note: ${record.notes}'),
                if (record.value == 'absent' && record.quote.isEmpty)
                  const Text(
                    'Assenza indicata manualmente dall’autore, senza citazione.',
                  ),
                const Text('Conservata in questo browser e indirizzo locale.'),
                const SizedBox(height: 8),
              ],
              Text(character.description),
              for (final proof in cell.evidence) ...[
                const Divider(height: 24),
                Text(
                  'Campo sorgente: ${proof.field}',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 6),
                SelectableText('“${proof.quote}”'),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (PhysciaPilot.inScope(row.taxon) &&
            PhysciaPilot.character(character.id) != null)
          TextButton(
            onPressed: reviewsFailed
                ? null
                : () {
                    Navigator.pop(context);
                    _editCell(row, character.id);
                  },
            child: const Text('Revisiona questa cella'),
          ),

        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Chiudi'),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ItalicTaxonPage(taxon: row.taxon),
              ),
            );
          },
          child: const Text('Scheda ITALIC'),
        ),
      ],
    ),
  );
}
