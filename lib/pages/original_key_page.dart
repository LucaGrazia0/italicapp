import 'package:flutter/material.dart';
import 'package:url_launcher/link.dart';
import '../data/identification_repository.dart';
import '../data/italic_reference_repository.dart';
import '../data/original_key_repository.dart';
import '../widgets/key_step_transition.dart';
import '../widgets/taxon_photo_card.dart';
import 'italic_taxon_page.dart';

class OriginalKeyPage extends StatefulWidget {
  const OriginalKeyPage({
    super.key,
    required this.entry,
    this.archive,
    this.reference,
  });
  final GenusKey entry;
  final Future<OriginalKeyArchive>? archive;
  final List<ItalicTaxon>? reference;
  @override
  State<OriginalKeyPage> createState() => _OriginalKeyPageState();
}

class _OriginalKeyPageState extends State<OriginalKeyPage> {
  OriginalKey? definition;
  List<ItalicTaxon> reference = [];
  bool loading = true, failed = false;
  int? number = 1;
  final history = <(int, int)>[];
  final scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final archive = await (widget.archive ?? OriginalKeyArchive.load());
      var taxa = widget.reference ?? <ItalicTaxon>[];
      if (widget.reference == null) {
        // The original key remains usable if the local checklist cannot load.
        try {
          final repo = ItalicReferenceRepository();
          await repo.load();
          taxa = repo.taxa;
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        definition = archive.forEntry(widget.entry);
        reference = taxa;
        loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          failed = true;
        });
      }
    }
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  void _choose(int index) {
    final current = number!;
    final lead = definition!.nodes[current]!.choices[index];
    setState(() {
      history.add((current, index));
      number = lead.target;
    });
    // The next couplet occupies the same reading position, below the app bar.
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  void _previous() {
    if (history.isEmpty) return;
    setState(() => number = history.removeLast().$1);
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  OriginalLead? get terminal => number != null || history.isEmpty
      ? null
      : definition!.nodes[history.last.$1]!.choices[history.last.$2];

  ItalicTaxon? _taxon(OriginalLead lead) {
    String normalize(String text) =>
        text.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    for (final taxon in reference) {
      if (taxon.italicId == lead.italicId &&
          [
            taxon.scientificName,
            ...taxon.synonyms,
          ].any((name) => normalize(name) == normalize(lead.name!))) {
        return taxon;
      }
    }
    return null;
  }

  void _candidates() {
    final names = terminal != null
        ? [terminal!.name!]
        : (definition!.candidates(number!).toList()..sort());
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                '${names.length} taxa nei rami rimasti',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (number != null && definition!.unresolved(number!).isNotEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Sono presenti anche continuazioni non disponibili nella fonte.',
                ),
              ),
            Expanded(
              child: ListView.builder(
                itemCount: names.length,
                itemBuilder: (_, index) => ListTile(
                  title: Text(
                    names[index],
                    style: const TextStyle(fontStyle: FontStyle.italic),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _fullText(OriginalKey key) {
    final nodes = key.nodes.values.toList()
      ..sort((a, b) => a.number.compareTo(b.number));
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .85,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Testo completo · ${nodes.length} bivi',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: nodes.length,
                itemBuilder: (_, index) {
                  final node = nodes[index];
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bivio ${node.number}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (key.unreachableCouplets.contains(node.number))
                          const Text(
                            'Non raggiungibile dai collegamenti pubblicati.',
                          ),
                        for (final lead in node.choices)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: SelectableText(
                              '${lead.label}\n→ ${lead.name ?? "Bivio ${lead.target}"}',
                            ),
                          ),
                        const Divider(),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _source() => Link(
    uri: widget.entry.url,
    target: LinkTarget.blank,
    builder: (_, follow) => OutlinedButton.icon(
      onPressed: follow,
      icon: const Icon(Icons.open_in_new),
      label: const Text('Confronta con ITALIC · online'),
    ),
  );

  Widget _details(OriginalKey key) => ExpansionTile(
    key: ValueKey('original-key-source-${key.id}'),
    title: const Text('Autori e fonte'),
    childrenPadding: const EdgeInsets.all(16),
    expandedCrossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SelectableText(key.title),
      const SizedBox(height: 8),
      SelectableText(key.credits),
      if (key.introduction.isNotEmpty) ...[
        const SizedBox(height: 12),
        SelectableText(key.introduction),
      ],
      const SizedBox(height: 12),
      Text(
        'Testi e numerazione originali · CC BY-SA 4.0\nCopia acquisita il ${key.accessedOn}.',
      ),
      const SizedBox(height: 8),
      const Text(
        'Le illustrazioni online dei bivi non sono incluse. Le schede locali mantengono le foto offline disponibili.',
      ),
      const SizedBox(height: 12),
      _source(),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final key = definition;
    final end = terminal;
    final node = key?.nodes[number];
    final namesCount = end != null
        ? 1
        : key?.candidates(number ?? 1).length ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.entry.genus} · chiave originale'),
        actions: [
          if (history.isNotEmpty) ...[
            IconButton(
              key: const ValueKey('original-key-back'),
              tooltip: 'Bivio precedente',
              onPressed: _previous,
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              tooltip: 'Ricomincia',
              onPressed: () {
                setState(() {
                  history.clear();
                  number = 1;
                });
                if (scroll.hasClients) scroll.jumpTo(0);
              },
              icon: const Icon(Icons.restart_alt),
            ),
          ],
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: ListView(
                  controller: scroll,
                  padding: const EdgeInsets.all(20),
                  children: key == null
                      ? [
                          Text(
                            failed
                                ? 'Copia offline non leggibile. Riapri la pagina o aggiorna l’app.'
                                : 'Questa chiave non è disponibile nella copia offline. Il percorso originale non è stato sostituito con un’altra chiave.',
                          ),
                          const SizedBox(height: 16),
                          _source(),
                        ]
                      : [
                          Text(
                            key.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          if (key.missingTargets.isNotEmpty ||
                              key.unreachableCouplets.isNotEmpty)
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Collegamenti incompleti nella fonte',
                                    ),
                                    Text(
                                      '${key.missingTargets.length} continuazioni mancanti · ${key.unreachableCouplets.length} bivi non raggiungibili. Testi e numeri sono conservati senza correzioni automatiche.',
                                    ),
                                    TextButton(
                                      onPressed: () => _fullText(key),
                                      child: const Text(
                                        'Consulta tutti i bivi',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          TextButton.icon(
                            key: const ValueKey('original-key-candidates'),
                            onPressed: _candidates,
                            icon: const Icon(Icons.list_alt),
                            label: Text(
                              '$namesCount taxa rimasti · mostra elenco',
                            ),
                          ),
                          KeyStepTransition(
                            step: (number, history.length),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (node != null) ...[
                                  Text(
                                    'Bivio ${node.number}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineSmall,
                                  ),
                                  const SizedBox(height: 12),
                                  for (var i = 0; i < node.choices.length; i++)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      child: OutlinedButton(
                                        key: ValueKey('original-choice-$i'),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.all(20),
                                          alignment: Alignment.centerLeft,
                                          minimumSize: const Size.fromHeight(
                                            80,
                                          ),
                                        ),
                                        onPressed: () => _choose(i),
                                        child: Text(
                                          node.choices[i].label,
                                          style: const TextStyle(fontSize: 18),
                                        ),
                                      ),
                                    ),
                                  TextButton(
                                    onPressed: _candidates,
                                    child: const Text(
                                      'Non so · confronta i taxa rimasti',
                                    ),
                                  ),
                                ] else if (end != null) ...[
                                  Text(
                                    end.name!,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(fontStyle: FontStyle.italic),
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Esito della chiave originale · da verificare sul campione.',
                                  ),
                                  if (_taxon(end) case final taxon?) ...[
                                    TaxonPhotoCard(taxon: taxon),
                                    FilledButton.icon(
                                      onPressed: () => Navigator.push(
                                        context,
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              ItalicTaxonPage(taxon: taxon),
                                        ),
                                      ),
                                      icon: const Icon(Icons.menu_book),
                                      label: const Text(
                                        'Apri scheda specie · offline',
                                      ),
                                    ),
                                  ],
                                  if (end.description.isNotEmpty)
                                    ExpansionTile(
                                      title: const Text(
                                        'Descrizione nella chiave',
                                      ),
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: SelectableText(
                                            end.description,
                                          ),
                                        ),
                                      ],
                                    ),
                                ] else ...[
                                  Text(
                                    'Continuazione $number non disponibile nella fonte acquisita.',
                                  ),
                                  const Text(
                                    'Il ramo resta segnalato: nessuna specie viene dedotta automaticamente.',
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          OutlinedButton.icon(
                            onPressed: () => _fullText(key),
                            icon: const Icon(Icons.article_outlined),
                            label: const Text('Testo completo · offline'),
                          ),
                          _details(key),
                        ],
                ),
              ),
            ),
    );
  }
}
