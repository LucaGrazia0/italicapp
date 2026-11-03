import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/character_matrix_repository.dart';
import '../data/character_dictionary_repository.dart';
import '../services/character_dictionary.dart';
import '../data/character_review_repository.dart';
import '../models/character_review.dart';
import '../services/physcia_review_engine.dart';
import 'character_review_page.dart';
import 'physcia_key_page.dart';
import 'character_matrix_page.dart';
import 'physcia_dictionary_audit_page.dart';

class PhysciaReviewPage extends StatefulWidget {
  const PhysciaReviewPage({
    super.key,
    this.matrix,
    this.dictionary,
    this.matrixRepository,
    this.reviewRepository,
    this.initialTaxonId,
    this.initialCharacterId,
  });
  final CharacterMatrix? matrix;
  final CharacterDictionary? dictionary;
  final CharacterMatrixRepository? matrixRepository;
  final CharacterReviewRepository? reviewRepository;
  final int? initialTaxonId;
  final String? initialCharacterId;
  @override
  State<PhysciaReviewPage> createState() => _PhysciaReviewPageState();
}

class _PhysciaReviewPageState extends State<PhysciaReviewPage> {
  late final CharacterReviewRepository repository;
  CharacterMatrix? matrix;
  CharacterDictionary? dictionary;
  final proposals = <String, ReviewProposal>{};
  ReviewRegistry registry = ReviewRegistry([]);
  bool loading = true, failed = false, openedInitial = false;
  final search = TextEditingController();

  @override
  void initState() {
    super.initState();
    repository = widget.reviewRepository ?? CharacterReviewRepository();
    _load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      final data =
          matrix ??
          widget.matrix ??
          await (widget.matrixRepository ?? CharacterMatrixRepository()).load();
      final terms =
          dictionary ??
          widget.dictionary ??
          await CharacterDictionaryRepository().load();
      if (proposals.isEmpty) {
        for (final row in data.taxa.where(
          (r) => PhysciaPilot.inScope(r.taxon),
        )) {
          for (final c in PhysciaPilot.characters) {
            proposals['${row.taxon.italicId}:${c.id}'] = PhysciaPilot.proposal(
              row,
              c,
              dictionary: terms,
            );
          }
        }
      }
      final records = await repository.all();
      if (!mounted) return;
      setState(() {
        matrix = data;
        dictionary = terms;
        registry = ReviewRegistry(records);
      });
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
    if (mounted) setState(() => loading = false);
    if (mounted && !failed && !openedInitial && widget.initialTaxonId != null) {
      openedInitial = true;
      final rows = matrix!.taxa.where(
        (r) =>
            r.taxon.italicId == widget.initialTaxonId &&
            PhysciaPilot.inScope(r.taxon),
      );
      final character = PhysciaPilot.character(widget.initialCharacterId ?? '');
      if (rows.isNotEmpty && character != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _edit(rows.first, character);
        });
      }
    }
  }

  Future<void> _edit(MatrixTaxon row, PilotCharacter c) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CharacterReviewPage(
          row: row,
          dictionary: dictionary,
          character: c,
          registry: registry,
          repository: repository,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _backup() => showDialog<void>(
    context: context,
    builder: (_) {
      final text = const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 1,
        'scope': 'Physcia manual review history',
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'reviews': registry.records.map((r) => r.toMap()).toList(),
      });
      return AlertDialog(
        title: const Text('Backup delle revisioni · JSON'),
        content: SizedBox(
          width: 700,
          child: SingleChildScrollView(child: SelectableText(text)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Chiudi'),
          ),
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Backup copiato: incollalo e salvalo in un file JSON.',
                    ),
                  ),
                );
              }
            },
            child: const Text('Copia JSON'),
          ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final rows =
        matrix?.taxa.where((r) => PhysciaPilot.inScope(r.taxon)).toList() ??
        <MatrixTaxon>[];
    var reviewed = 0, usable = 0, stale = 0;
    for (final row in rows) {
      for (final c in PhysciaPilot.characters) {
        if (PhysciaPilot.absenceFor(registry, row.taxon, c.id) != null) {
          continue;
        }
        final record = registry.latest(row.taxon.italicId!, c.id);
        if (record == null) continue;
        if (!record.matches(row.taxon)) {
          stale++;
          continue;
        }
        if (record.isReviewed) reviewed++;
        if (PhysciaPilot.usable(record, row.taxon, c)) usable++;
      }
    }
    final query = search.text.trim().toLowerCase();
    final filtered = rows
        .where(
          (r) =>
              r.taxon.scientificName.toLowerCase().contains(query) ||
              r.taxon.italicId.toString() == query,
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Revisione matrice · Physcia'),
        actions: [
          IconButton(
            key: const ValueKey('physcia-open-dictionary-audit'),
            tooltip: 'Riesamina le Physcia con il dizionario',
            icon: const Icon(Icons.manage_search),
            onPressed: loading || failed
                ? null
                : () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PhysciaDictionaryAuditPage(
                          matrix: matrix!,
                          dictionary: dictionary!,
                          registry: registry,
                          repository: repository,
                        ),
                      ),
                    );
                    if (mounted) await _load();
                  },
          ),
          IconButton(
            key: const ValueKey('physcia-open-matrix'),
            tooltip: 'Visualizza modifiche nella matrice',
            icon: const Icon(Icons.table_chart_outlined),
            onPressed: loading || failed
                ? null
                : () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CharacterMatrixPage(
                          dictionary: dictionary,
                          matrix: matrix,
                          reviewRepository: repository,
                        ),
                      ),
                    );
                    if (mounted) await _load();
                  },
          ),
          IconButton(
            tooltip: 'Backup JSON delle revisioni',
            onPressed: loading || failed ? null : _backup,
            icon: const Icon(Icons.content_copy),
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
                  const Text(
                    'Impossibile caricare matrice o revisioni locali.',
                  ),
                  TextButton(onPressed: _load, child: const Text('Riprova')),
                ],
              ),
            )
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${rows.length} taxa × ${PhysciaPilot.characters.length} caratteri · $reviewed celle revisionate · $usable valori stabili utilizzabili',
                            key: const ValueKey('physcia-review-count'),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          if (stale > 0)
                            Text(
                              '$stale revisioni con fonte cambiata: valori sospesi.',
                            ),
                          const SizedBox(height: 8),
                          const Text(
                            'Il dizionario propone tallo, colori, lobi, presenza, forme e tipi con le frasi di origine. Scegli una cella per controllare e salvare. Le tue revisioni hanno precedenza; le proposte restano da confermare.',
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Le modifiche salvate compaiono anche nella matrice (icona tabella in alto). Restano in questo browser e indirizzo locale. Usa Backup JSON per conservarne una copia.',
                          ),
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            key: const ValueKey('open-physcia-reviewed-key'),
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PhysciaKeyPage(
                                  matrix: matrix!,
                                  registry: registry,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.account_tree_outlined),
                            label: const Text(
                              'Prova libera della chiave revisionata',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            key: const ValueKey('physcia-review-search'),
                            controller: search,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Cerca una Physcia o un ID',
                              prefixIcon: Icon(Icons.search),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(
                              child: Text('Nessun taxon per questa ricerca.'),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                              itemCount: filtered.length,
                              itemBuilder: (_, index) {
                                final row = filtered[index];
                                return Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          row.taxon.scientificName,
                                          style: const TextStyle(
                                            fontStyle: FontStyle.italic,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text('ITALIC ID ${row.taxon.italicId}'),
                                        const SizedBox(height: 10),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            for (final c
                                                in PhysciaPilot.characters)
                                              _cell(row, c),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _cell(MatrixTaxon row, PilotCharacter c) {
    final absence = PhysciaPilot.absenceFor(registry, row.taxon, c.id);
    if (absence != null) {
      return ActionChip(
        key: ValueKey('review-cell-${row.taxon.italicId}-${c.id}'),
        avatar: const Icon(Icons.not_interested_outlined, size: 18),
        label: Text('${c.label}: Non applicabile'),
        tooltip:
            '${PhysciaPilot.absenceLabel(absence)} · ${absence.statusLabel}',
        onPressed: () => _edit(row, c),
      );
    }
    final record = registry.latest(row.taxon.italicId!, c.id);
    final current = record?.matches(row.taxon) == true;
    final usable = PhysciaPilot.usable(record, row.taxon, c);
    final proposal = proposals['${row.taxon.italicId}:${c.id}']!;
    final value = current ? record!.value : proposal.value;
    final status = record == null
        ? proposal.isCandidate
              ? 'Proposta dizionario'
              : proposal.status == 'needs_review'
              ? 'Da chiarire'
              : 'Non documentato'
        : !current
        ? 'Fonte cambiata'
        : record.statusLabel;
    return ActionChip(
      key: ValueKey('review-cell-${row.taxon.italicId}-${c.id}'),
      avatar: Icon(
        usable ? Icons.check_circle_outline : Icons.edit_outlined,
        size: 18,
      ),
      label: Text(
        '${c.label}: ${c.labelFor(value)} · $status',
        overflow: TextOverflow.ellipsis,
      ),
      tooltip: '${c.label} · ${c.labelFor(value)} · $status',
      onPressed: () => _edit(row, c),
    );
  }
}
