import 'package:flutter/material.dart';
import 'package:url_launcher/link.dart';
import '../data/identification_repository.dart';
import '../data/italic_reference_repository.dart';
import '../data/original_key_repository.dart';
import '../widgets/key_step_transition.dart';
import '../widgets/key_controls.dart';
import '../theme/app_theme.dart';
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
  final coupletAnchor = GlobalKey();

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
    _focusCouplet();
  }

  void _previous() {
    if (history.isEmpty) return;
    setState(() => number = history.removeLast().$1);
    _focusCouplet();
  }

  void _focusCouplet() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scroll.hasClients) return;
      final target = coupletAnchor.currentContext;
      if (target == null) {
        scroll.jumpTo(0);
        return;
      }
      Scrollable.ensureVisible(
        target,
        alignment: .04,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
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

  void _sheet(String title, List<Widget> slivers) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppTheme.ivory,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .82,
        minChildSize: .4,
        maxChildSize: .95,
        builder: (_, controller) => CustomScrollView(
          key: const ValueKey('original-key-sheet-scroll'),
          controller: controller,
          slivers: [
            SliverToBoxAdapter(
              child: KeySheetHeader(
                title: title,
                onClose: () => Navigator.pop(sheetContext),
              ),
            ),
            ...slivers,
            SliverToBoxAdapter(
              child: SizedBox(
                height: MediaQuery.paddingOf(sheetContext).bottom + 24,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _candidates() {
    final names = terminal != null
        ? [terminal!.name!]
        : (definition!.candidates(number!).toList()..sort());
    _sheet('${names.length} taxa nei rami rimasti', [
      if (number != null && definition!.unresolved(number!).isNotEmpty)
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
          sliver: SliverToBoxAdapter(
            child: KeyNotice(
              title: 'Esiti da approfondire',
              message:
                  'Sono presenti anche continuazioni non disponibili nella fonte.',
            ),
          ),
        ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList.builder(
          itemCount: names.length,
          itemBuilder: (_, index) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.eco_outlined,
                      color: AppTheme.forest,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      names[index],
                      style: const TextStyle(
                        fontSize: 17,
                        height: 1.5,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  void _fullText(OriginalKey key) {
    final nodes = key.nodes.values.toList()
      ..sort((a, b) => a.number.compareTo(b.number));
    _sheet('Testo completo · ${nodes.length} bivi', [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList.builder(
          itemCount: nodes.length,
          itemBuilder: (_, index) {
            final node = nodes[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 14),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Bivio ${node.number}',
                      style: const TextStyle(
                        fontSize: 19,
                        color: AppTheme.forest,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (key.unreachableCouplets.contains(node.number)) ...[
                      const SizedBox(height: 12),
                      const KeyNotice(
                        title: 'Collegamento da verificare',
                        message:
                            'Non raggiungibile dai collegamenti pubblicati.',
                      ),
                    ],
                    for (var i = 0; i < node.choices.length; i++) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Alternativa ${i == 0 ? "A" : "B"}',
                        style: const TextStyle(
                          color: AppTheme.forest,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        node.choices[i].label,
                        style: const TextStyle(fontSize: 16, height: 1.55),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 3),
                            child: Icon(
                              Icons.arrow_forward_rounded,
                              size: 18,
                              color: AppTheme.forest,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SelectableText(
                              node.choices[i].name ??
                                  'Continua al bivio ${node.choices[i].target}',
                              style: TextStyle(
                                color: AppTheme.forest,
                                height: 1.5,
                                fontWeight: FontWeight.w600,
                                fontStyle: node.choices[i].name == null
                                    ? FontStyle.normal
                                    : FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (i == 0) const Divider(height: 28),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }

  Widget _source() => Link(
    uri: widget.entry.url,
    target: LinkTarget.blank,
    builder: (_, follow) => KeyActionButton(
      onPressed: follow,
      icon: Icons.open_in_new,
      label: 'Confronta con ITALIC · online',
    ),
  );

  Widget _details(OriginalKey key) => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      key: ValueKey('original-key-source-${key.id}'),
      tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      leading: const Icon(Icons.info_outline, color: AppTheme.forest),
      title: const Text('Autori e fonte'),
      childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelectableText(
          key.title,
          style: const TextStyle(fontWeight: FontWeight.w700, height: 1.5),
        ),
        if (key.credits.isNotEmpty) ...[
          const SizedBox(height: 10),
          SelectableText(key.credits, style: const TextStyle(height: 1.5)),
        ],
        if (key.introduction.isNotEmpty) ...[
          const SizedBox(height: 14),
          SelectableText(
            key.introduction,
            style: const TextStyle(height: 1.55),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Testi e numerazione originali · CC BY-SA 4.0\nCopia acquisita il ${key.accessedOn}.',
          style: const TextStyle(height: 1.5),
        ),
        const SizedBox(height: 10),
        const Text(
          'Le illustrazioni online dei bivi non sono incluse. Le schede locali mantengono le foto offline disponibili.',
          style: TextStyle(height: 1.5),
        ),
        const SizedBox(height: 16),
        _source(),
      ],
    ),
  );

  void _restart() {
    setState(() {
      history.clear();
      number = 1;
    });
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  String _groupTitle(OriginalKey key) => key.title.replaceFirst(
    RegExp(
      r'^KEYS TO THE LICHENS OF ITALY\s*[-–]\s*\d+\)\s*',
      caseSensitive: false,
    ),
    '',
  );

  Widget _summary(OriginalKey key) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xFFE9F0E7),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Wrap(
          spacing: 7,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(Icons.offline_pin_outlined, size: 17, color: AppTheme.forest),
            Text(
              'Chiave originale · offline',
              style: TextStyle(
                color: AppTheme.forest,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Text(
          _groupTitle(key),
          style: const TextStyle(
            color: AppTheme.forest,
            fontSize: 17,
            height: 1.4,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );

  Widget _step(
    OriginalKey key,
    OriginalCouplet? node,
    OriginalLead? end,
  ) => KeyStepTransition(
    step: (number, history.length),
    child: Column(
      key: coupletAnchor,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (node != null) ...[
          Text(
            'Bivio ${node.number}',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: AppTheme.forest,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < node.choices.length; i++) ...[
            KeyChoiceCard(
              key: ValueKey('original-choice-$i'),
              letter: i == 0 ? 'A' : 'B',
              label: node.choices[i].label,
              onPressed: () => _choose(i),
            ),
            const SizedBox(height: 14),
          ],
          const SizedBox(height: 2),
          KeyActionButton(
            label: 'Non so · confronta i taxa rimasti',
            icon: Icons.help_outline,
            onPressed: _candidates,
          ),
        ] else if (end != null) ...[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFD4E0D4)),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Esito della chiave',
                  style: TextStyle(
                    color: AppTheme.forest,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  end.name!,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    height: 1.35,
                    color: AppTheme.forest,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Esito della chiave originale · da verificare sul campione.',
                  style: TextStyle(height: 1.5),
                ),
              ],
            ),
          ),
          if (_taxon(end) case final taxon?) ...[
            TaxonPhotoCard(taxon: taxon),
            const SizedBox(height: 4),
            KeyActionButton(
              primary: true,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ItalicTaxonPage(taxon: taxon),
                ),
              ),
              icon: Icons.menu_book_outlined,
              label: 'Apri scheda specie · offline',
            ),
          ],
          if (end.description.isNotEmpty) ...[
            const SizedBox(height: 14),
            Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                title: const Text('Descrizione nella chiave'),
                expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                children: [
                  SelectableText(
                    end.description,
                    style: const TextStyle(fontSize: 16, height: 1.55),
                  ),
                ],
              ),
            ),
          ],
        ] else ...[
          KeyNotice(
            title: 'Esito da approfondire',
            message:
                'Continuazione $number non disponibile nella fonte acquisita.',
          ),
          const SizedBox(height: 12),
          const Text(
            'Il ramo resta segnalato: nessuna specie viene dedotta automaticamente.',
            style: TextStyle(height: 1.5),
          ),
        ],
      ],
    ),
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
        title: Text(
          widget.entry.genus,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (history.isNotEmpty)
            IconButton(
              key: const ValueKey('original-key-back'),
              tooltip: 'Bivio precedente',
              onPressed: _previous,
              icon: const Icon(Icons.undo),
            ),
          if (key != null) ...[
            IconButton(
              key: const ValueKey('original-key-candidates-toolbar'),
              tooltip: 'Taxa rimasti',
              onPressed: _candidates,
              icon: const Icon(Icons.format_list_bulleted_rounded),
            ),
            PopupMenuButton<String>(
              tooltip: 'Altre opzioni',
              onSelected: (action) {
                if (action == 'restart') _restart();
                if (action == 'text') _fullText(key);
              },
              itemBuilder: (_) => [
                if (history.isNotEmpty)
                  const PopupMenuItem(
                    value: 'restart',
                    child: Text('Ricomincia'),
                  ),
                const PopupMenuItem(
                  value: 'text',
                  child: Text('Testo completo · offline'),
                ),
              ],
            ),
          ],
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              top: false,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: ListView(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                    children: key == null
                        ? [
                            KeyNotice(
                              title: failed
                                  ? 'Copia offline non leggibile'
                                  : 'Copia offline non disponibile',
                              message: failed
                                  ? 'Copia offline non leggibile. Riapri la pagina o aggiorna l’app.'
                                  : 'Questa chiave non è disponibile nella copia offline. Il percorso originale non è stato sostituito con un’altra chiave.',
                            ),
                            const SizedBox(height: 16),
                            _source(),
                          ]
                        : [
                            _summary(key),
                            const SizedBox(height: 12),
                            KeyActionButton(
                              key: const ValueKey('original-key-candidates'),
                              onPressed: _candidates,
                              icon: Icons.format_list_bulleted_rounded,
                              label: '$namesCount taxa rimasti',
                              subtitle: 'Mostra elenco',
                              trailing: true,
                            ),
                            if (key.missingTargets.isNotEmpty ||
                                key.unreachableCouplets.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              KeyNotice(
                                title: 'Collegamenti incompleti nella fonte',
                                message:
                                    '${key.missingTargets.length} continuazioni mancanti · ${key.unreachableCouplets.length} bivi non raggiungibili. Testi e numeri sono conservati senza correzioni automatiche.',
                                action: KeyActionButton(
                                  onPressed: () => _fullText(key),
                                  icon: Icons.article_outlined,
                                  label: 'Consulta tutti i bivi',
                                ),
                              ),
                            ],
                            const SizedBox(height: 24),
                            _step(key, node, end),
                            const SizedBox(height: 24),
                            KeyActionButton(
                              onPressed: () => _fullText(key),
                              icon: Icons.article_outlined,
                              label: 'Testo completo · offline',
                            ),
                            const SizedBox(height: 12),
                            _details(key),
                          ],
                  ),
                ),
              ),
            ),
    );
  }
}
