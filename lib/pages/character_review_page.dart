import 'package:flutter/material.dart';
import '../data/character_matrix_repository.dart';
import '../data/character_review_repository.dart';
import '../data/character_dictionary_repository.dart';
import '../models/character_review.dart';
import '../services/physcia_review_engine.dart';
import '../services/character_dictionary.dart';
import 'character_dictionary_page.dart';

class CharacterReviewPage extends StatefulWidget {
  const CharacterReviewPage({
    super.key,
    required this.row,
    required this.character,
    required this.registry,
    required this.repository,
    this.dictionary,
  });
  final MatrixTaxon row;
  final CharacterDictionary? dictionary;
  final PilotCharacter character;
  final ReviewRegistry registry;
  final CharacterReviewRepository repository;
  @override
  State<CharacterReviewPage> createState() => _CharacterReviewPageState();
}

class _CharacterReviewPageState extends State<CharacterReviewPage> {
  final form = GlobalKey<FormState>();
  late final TextEditingController reviewer, quote, notes;
  late final CharacterReview? previous;
  late ReviewProposal proposal;
  late String value;
  String status = 'draft';
  bool saving = false, loading = true, loadFailed = false;
  String? error;

  @override
  void initState() {
    super.initState();
    previous = widget.registry.latest(
      widget.row.taxon.italicId!,
      widget.character.id,
    );
    reviewer = TextEditingController(text: previous?.reviewer ?? '');
    quote = TextEditingController();
    notes = TextEditingController();
    _loadProposal();
  }

  Future<void> _loadProposal() async {
    setState(() {
      loading = true;
      loadFailed = false;
    });
    try {
      final dictionary =
          widget.dictionary ?? await CharacterDictionaryRepository().load();
      if (!mounted) return;
      proposal = PhysciaPilot.proposal(
        widget.row,
        widget.character,
        dictionary: dictionary,
      );
      final current =
          previous?.matches(widget.row.taxon) == true &&
          widget.character.validValue(previous?.value);
      value = current ? previous!.value : proposal.value;
      quote.text = current ? previous!.quote : proposal.quote;
      notes.text = current ? previous!.notes : '';
    } catch (_) {
      if (mounted) setState(() => loadFailed = true);
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  void dispose() {
    reviewer.dispose();
    quote.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!form.currentState!.validate() || saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final record = CharacterReview.create(
        taxon: widget.row.taxon,
        characterId: widget.character.id,
        value: value,
        status: status,
        reviewer: reviewer.text,
        quote: quote.text,
        notes: notes.text,
        previous: previous,
      );
      await widget.repository.save(record, widget.row.taxon);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Modifica salvata nella matrice · ${record.statusLabel}',
            ),
          ),
        );
        Navigator.pop(context, record);
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is ReviewConflict || e is ReviewNotApplicable
              ? e.toString()
              : 'Salvataggio non riuscito. Controlla i campi e riprova: la bozza resta disponibile.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void _useHistory(CharacterReview record) {
    setState(() {
      value = record.value;
      status = 'draft';
      quote.text = (widget.row.taxon.description ?? '').contains(record.quote)
          ? record.quote
          : '';
      notes.text = record.notes;
    });
  }

  Future<void> _searchDictionary() async {
    final hit = await Navigator.push<DictionaryHit>(
      context,
      MaterialPageRoute(
        builder: (_) => CharacterDictionaryPage(
          dictionary: widget.dictionary,
          sourceText: widget.row.taxon.description ?? '',
          initialConcept: widget.character.id,
          pickEvidence: true,
        ),
      ),
    );
    if (!mounted || hit == null) return;
    setState(() {
      quote.text = hit.quote;
      status = 'draft';
      if (hit.state != null) {
        final note =
            'Dizionario · ${hit.character.label}: ${hit.state!.label} (${hit.statusLabel}).';
        notes.text = notes.text.trim().isEmpty ? note : '${notes.text}\n$note';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final taxon = widget.row.taxon;
    final definition = widget.character;
    final history = widget.registry.history(taxon.italicId!, definition.id);
    final absence = PhysciaPilot.absenceFor(
      widget.registry,
      taxon,
      definition.id,
    );
    if (absence != null) {
      return Scaffold(
        appBar: AppBar(title: Text(definition.label)),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              taxon.scientificName,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            const Text(
              'Non applicabile',
              key: ValueKey('review-not-applicable'),
            ),
            Text(
              '${PhysciaPilot.absenceLabel(absence)}: questo carattere non è applicabile. Per riattivarlo modifica prima la cella ${PhysciaPilot.character(absence.characterId)!.label}.',
            ),
            const SizedBox(height: 12),
            Text(
              '${PhysciaPilot.absenceLabel(absence)} · ${absence.statusLabel} · ${absence.reviewer}',
            ),
            if (history.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text(
                'Le versioni precedenti restano conservate nella cronologia.',
              ),
              for (final record in history)
                ListTile(
                  title: Text(
                    '${definition.labelFor(record.value)} · ${record.statusLabel}',
                  ),
                  subtitle: Text(
                    '${record.reviewer} · versione ${record.version}',
                  ),
                ),
            ],
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Torna alle revisioni'),
            ),
          ],
        ),
      );
    }
    if (loading || loadFailed) {
      return Scaffold(
        appBar: AppBar(title: Text('Revisiona · ${definition.label}')),
        body: Center(
          child: loading
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Impossibile caricare le proposte del dizionario.',
                    ),
                    TextButton(
                      onPressed: _loadProposal,
                      child: const Text('Riprova'),
                    ),
                  ],
                ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text('Revisiona · ${definition.label}')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: FilledButton.icon(
            key: const ValueKey('save-character-review'),
            onPressed: saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(
              saving
                  ? 'Salvataggio…'
                  : status == 'reviewed'
                  ? 'Salva revisione manuale'
                  : 'Salva ${status == "clarify" ? "come da chiarire" : "bozza"}',
            ),
          ),
        ),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Form(
            key: form,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  taxon.scientificName,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontStyle: FontStyle.italic),
                ),
                Text('ITALIC ID ${taxon.italicId} · ${definition.label}'),
                const SizedBox(height: 12),
                Text(definition.help),
                TextButton.icon(
                  key: const ValueKey('review-open-dictionary'),
                  onPressed: saving ? null : _searchDictionary,
                  icon: const Icon(Icons.manage_search),
                  label: const Text(
                    'Cerca termini, forme e tipi nella descrizione',
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'La revisione è locale e attribuita al nome inserito; non è una certificazione scientifica. Solo valori stabili revisionati e con fonte invariata vengono usati nella prova della chiave.',
                ),
                if (previous != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'Ultima versione ${previous!.version}: ${previous!.statusLabel} · ${previous!.reviewer}'
                      '${previous!.matches(taxon) ? "" : " · FONTE CAMBIATA: valore sospeso"}',
                    ),
                  ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Proposta del dizionario · ${definition.labelFor(proposal.value)}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(proposal.explanation),
                        if (proposal.isCandidate)
                          TextButton.icon(
                            key: const ValueKey(
                              'review-use-dictionary-proposal',
                            ),
                            onPressed: saving
                                ? null
                                : () => setState(() {
                                    value = proposal.value;
                                    quote.text = proposal.quote;
                                    status = 'draft';
                                  }),
                            icon: const Icon(Icons.edit_note),
                            label: const Text('Usa proposta come bozza'),
                          ),
                        if (proposal.quote.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          SelectableText('“${proposal.quote}”'),
                          TextButton(
                            onPressed: saving
                                ? null
                                : () => setState(() {
                                    quote.text = proposal.quote;
                                    status = 'draft';
                                  }),
                            child: const Text(
                              'Usa citazione proposta come bozza',
                            ),
                          ),
                        ],
                        if (proposal.hits.length > 1)
                          ExpansionTile(
                            title: Text(
                              'Tutte le evidenze (${proposal.hits.length})',
                            ),
                            children: [
                              for (final hit in proposal.hits)
                                ListTile(
                                  title: Text(
                                    '${hit.label} · ${hit.statusLabel}',
                                  ),
                                  subtitle: SelectableText('“${hit.quote}”'),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (definition.multiple)
                  InputDecorator(
                    key: ValueKey('review-value-$value'),
                    decoration: const InputDecoration(
                      labelText: 'Valori del carattere · scelta multipla',
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Seleziona tutti gli stati documentati. Sfumature, localizzazioni e condizioni restano nella citazione.',
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final option in definition.values.entries)
                              FilterChip(
                                key: ValueKey('review-option-${option.key}'),
                                label: Text(option.value),
                                selected: definition
                                    .selected(value)
                                    .contains(option.key),
                                onSelected: saving
                                    ? null
                                    : (selected) => setState(() {
                                        if (!definition.stable(option.key)) {
                                          value = option.key;
                                        } else {
                                          final chosen = definition
                                              .selected(value)
                                              .where(definition.stable)
                                              .toSet();
                                          if (selected) {
                                            chosen.add(option.key);
                                          } else {
                                            chosen.remove(option.key);
                                          }
                                          value = definition.encode(chosen);
                                        }
                                      }),
                              ),
                          ],
                        ),
                      ],
                    ),
                  )
                else
                  DropdownButtonFormField<String>(
                    key: ValueKey('review-value-$value'),
                    initialValue: value,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Valore del carattere',
                    ),
                    items: definition.values.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(
                              e.value,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: saving
                        ? null
                        : (v) => setState(() => value = v!),
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey('review-status-$status'),
                  initialValue: status,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Stato della revisione',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'draft',
                      child: Text('Bozza · non usata nella chiave'),
                    ),
                    DropdownMenuItem(
                      value: 'clarify',
                      child: Text('Da chiarire · non usata nella chiave'),
                    ),
                    DropdownMenuItem(
                      value: 'reviewed',
                      child: Text('Revisionato manualmente'),
                    ),
                  ],
                  onChanged: saving ? null : (v) => setState(() => status = v!),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('review-author'),
                  controller: reviewer,
                  enabled: !saving,
                  decoration: const InputDecoration(
                    labelText: 'Autore della revisione (nome o iniziali)',
                  ),
                  validator: (v) => (v ?? '').trim().isEmpty
                      ? 'Inserisci autore o iniziali.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('review-quote'),
                  controller: quote,
                  enabled: !saving,
                  minLines: 3,
                  maxLines: 7,
                  decoration: InputDecoration(
                    labelText: value == 'absent'
                        ? 'Citazione (facoltativa per Assente)'
                        : 'Citazione esatta dalla descrizione',
                    helperText: value == 'absent'
                        ? 'Puoi lasciare vuoto: l’assenza sarà una tua valutazione manuale.'
                        : 'Conserva la frase e le condizioni che sostengono il valore.',
                    helperMaxLines: 3,
                  ),
                  validator: (v) {
                    final text = (v ?? '').trim();
                    if (text.isEmpty &&
                        !['unknown', 'absent'].contains(value)) {
                      return 'Serve una citazione per questo valore.';
                    }
                    if (text.isNotEmpty &&
                        !(taxon.description ?? '').contains(text)) {
                      return 'La citazione non è presente esattamente nella descrizione.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('review-notes'),
                  controller: notes,
                  enabled: !saving,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Note e motivazione (facoltative per Assente)',
                  ),
                  validator: (v) =>
                      ['variable', 'other'].contains(value) &&
                          (v ?? '').trim().isEmpty
                      ? 'Descrivi variabilità, condizioni o altro stato.'
                      : null,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Autore e data saranno conservati nella nuova versione. Le versioni precedenti rimangono nella cronologia.',
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error!,
                      key: const ValueKey('review-save-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const Divider(height: 32),
                Text(
                  'Descrizione integrale ITALIC · fonte da controllare',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                SelectableText(
                  (taxon.description ?? '').isEmpty
                      ? 'Descrizione non disponibile.'
                      : taxon.description!,
                  key: const ValueKey('review-source-description'),
                ),
                if ((taxon.note ?? '').isNotEmpty) ...[
                  const Divider(height: 28),
                  Text(
                    'Note ITALIC · contesto da considerare',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  SelectableText(taxon.note!),
                ],
                if (history.isNotEmpty) ...[
                  const Divider(height: 32),
                  ExpansionTile(
                    title: Text('Cronologia della cella (${history.length})'),
                    children: [
                      for (final r in history)
                        ListTile(
                          title: Text(
                            'v${r.version} · ${definition.labelFor(r.value)} · ${r.statusLabel}',
                          ),
                          subtitle: Text(
                            '${r.reviewer} · ${r.createdAt.toLocal()}\n${r.matches(taxon) ? "Fonte invariata" : "Fonte diversa: valore sospeso"}\n“${r.quote}”\n${r.notes}',
                          ),
                          trailing: IconButton(
                            tooltip: 'Riprendi come bozza',
                            icon: const Icon(Icons.restore),
                            onPressed: saving ? null : () => _useHistory(r),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
