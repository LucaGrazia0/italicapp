import 'package:flutter/material.dart';
import '../data/character_matrix_repository.dart';
import '../data/character_review_repository.dart';
import '../models/character_review.dart';
import '../services/character_dictionary.dart';
import '../services/physcia_dictionary_audit.dart';
import '../services/physcia_review_engine.dart';
import 'character_review_page.dart';

class PhysciaDictionaryAuditPage extends StatefulWidget {
  const PhysciaDictionaryAuditPage({
    super.key,
    required this.matrix,
    required this.dictionary,
    required this.registry,
    required this.repository,
  });
  final CharacterMatrix matrix;
  final CharacterDictionary dictionary;
  final ReviewRegistry registry;
  final CharacterReviewRepository repository;
  @override
  State<PhysciaDictionaryAuditPage> createState() =>
      _PhysciaDictionaryAuditPageState();
}

class _PhysciaDictionaryAuditPageState
    extends State<PhysciaDictionaryAuditPage> {
  late ReviewRegistry registry;
  late List<PhysciaAuditCell> cells;
  PhysciaAuditStatus? filter = PhysciaAuditStatus.available;
  final search = TextEditingController();
  bool refreshFailed = false;
  @override
  void initState() {
    super.initState();
    registry = widget.registry;
    _analyze();
  }

  void _analyze() {
    cells = PhysciaDictionaryAudit().analyze(
      widget.matrix,
      widget.dictionary,
      registry,
    );
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> _edit(PhysciaAuditCell cell, [PilotCharacter? related]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CharacterReviewPage(
          row: cell.row,
          character: related ?? cell.character,
          registry: registry,
          repository: widget.repository,
          dictionary: widget.dictionary,
        ),
      ),
    );
    if (!mounted) return;
    try {
      final records = await widget.repository.all();
      if (!mounted) return;
      setState(() {
        registry = ReviewRegistry(records);
        refreshFailed = false;
        _analyze();
      });
    } catch (_) {
      if (mounted) setState(() => refreshFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = search.text.trim().toLowerCase();
    int count(PhysciaAuditStatus s) => cells.where((c) => c.status == s).length;
    final shown = cells
        .where(
          (c) =>
              (filter == null || c.status == filter) &&
              (query.isEmpty ||
                  c.row.taxon.scientificName.toLowerCase().contains(query) ||
                  c.row.taxon.italicId.toString() == query ||
                  c.character.label.toLowerCase().contains(query) ||
                  c.character.id.contains(query)),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Physcia · analisi del dizionario')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${cells.length} celle analizzate · ${count(PhysciaAuditStatus.available)} proposte disponibili · ${count(PhysciaAuditStatus.compare)} confronti da fare',
                      key: const ValueKey('physcia-audit-count'),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Ricerca automatica sulle descrizioni originali. Le segnalazioni sono proposte di lettura: nessuna revisione è modificata o approvata automaticamente.',
                    ),
                    if (refreshFailed)
                      const Text(
                        'Impossibile rileggere il registro: risultati della lettura precedente. Riapri questa pagina per aggiornare.',
                      ),
                    const SizedBox(height: 10),
                    TextField(
                      key: const ValueKey('physcia-audit-search'),
                      controller: search,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Cerca taxon, ID o carattere',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      key: const ValueKey('physcia-audit-filter'),
                      initialValue: filter?.name ?? 'all',
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Risultati'),
                      items: [
                        const DropdownMenuItem(
                          value: 'all',
                          child: Text('Tutti i caratteri'),
                        ),
                        for (final s in PhysciaAuditStatus.values)
                          DropdownMenuItem(
                            value: s.name,
                            child: Text('${s.label} (${count(s)})'),
                          ),
                      ],
                      onChanged: (v) => setState(
                        () => filter = v == 'all'
                            ? null
                            : PhysciaAuditStatus.values.byName(v!),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: shown.isEmpty
                    ? const Center(
                        child: Text('Nessun risultato per questi filtri.'),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                        itemCount: shown.length,
                        itemBuilder: (_, i) => _card(shown[i]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(PhysciaAuditCell cell) => Card(
    key: ValueKey(
      'physcia-audit-${cell.row.taxon.italicId}-${cell.character.id}',
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${cell.row.taxon.scientificName} · ID ${cell.row.taxon.italicId}',
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
          Text(
            cell.character.label,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(cell.status.label),
          const SizedBox(height: 6),
          if (cell.record case final record?)
            Text(
              'Salvato: ${cell.character.labelFor(record.value)} · ${record.statusLabel}',
            )
          else
            const Text('Nessuna revisione salvata per questa cella.'),
          Text('Dizionario: ${cell.character.labelFor(cell.proposal.value)}'),
          Text(cell.message),
          if (cell.record?.quote.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            const Text('Citazione salvata'),
            SelectableText('“${cell.record!.quote}”'),
          ],
          if (cell.proposal.quote.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Evidenza del dizionario'),
            SelectableText('“${cell.proposal.quote}”'),
          ],
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: () => _edit(cell),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Apri revisione'),
              ),
              if (cell.relatedCharacter case final related?)
                TextButton(
                  onPressed: () => _edit(cell, related),
                  child: Text('Apri ${related.label}'),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}
