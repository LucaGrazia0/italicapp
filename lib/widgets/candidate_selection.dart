import 'package:flutter/material.dart';
import '../app_store.dart';
import '../data/italic_reference_repository.dart';
import '../models/identification_path.dart';
import '../models/observation.dart';
import '../pages/italic_taxon_page.dart';
import '../services/diary_navigation.dart';

/// An explicit user decision, independent of automatic candidate filtering.
/// Commit a copy first: a failed write must not change the diary in memory.
class CandidateSelectionButton extends StatefulWidget {
  const CandidateSelectionButton({
    super.key,
    required this.taxon,
    required this.observation,
    required this.store,
    required this.path,
    this.disabled = false,
    this.onBusy,
    this.onSaved,
  });
  final ItalicTaxon taxon;
  final Observation observation;
  final AppStore store;
  final IdentificationPath Function() path;
  final bool disabled;
  final ValueChanged<bool>? onBusy;
  final ValueChanged<IdentificationPath>? onSaved;
  @override
  State<CandidateSelectionButton> createState() =>
      _CandidateSelectionButtonState();
}

class _CandidateSelectionButtonState extends State<CandidateSelectionButton> {
  bool working = false;
  Future<void> _choose() async {
    if (working || widget.disabled) return;
    setState(() => working = true);
    widget.onBusy?.call(true);
    try {
      final path = widget.path();
      final original = widget.observation;
      final updated = Observation.fromMap(original.toMap())
        ..rank = IdentificationRank.species
        ..taxonItalicId = widget.taxon.italicId
        ..taxonName = widget.taxon.scientificName
        ..identificationPath = path;
      await widget.store.save(updated);
      original
        ..rank = updated.rank
        ..taxonItalicId = updated.taxonItalicId
        ..taxonName = updated.taxonName
        ..identificationPath = path;
      if (mounted) {
        widget.onSaved?.call(path);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Identificazione salvata: ${updated.taxonName}'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Identificazione non salvata. Il nome e il percorso precedenti restano intatti. Riprova.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => working = false);
        widget.onBusy?.call(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (widget.observation.rank == IdentificationRank.species &&
          widget.observation.taxonName == widget.taxon.scientificName)
        const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Text('Scelto nel diario'),
        ),
      FilledButton.icon(
        key: ValueKey('choose-candidate-${widget.taxon.italicId}'),
        onPressed: working || widget.disabled ? null : _choose,
        icon: const Icon(Icons.check_circle_outline),
        label: Text(working ? 'Salvataggio…' : 'Scegli questo candidato'),
      ),
      if (widget.observation.rank == IdentificationRank.species &&
          widget.observation.taxonName == widget.taxon.scientificName)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OutlinedButton.icon(
            key: ValueKey('return-to-diary-${widget.taxon.italicId}'),
            onPressed: working
                ? null
                : () => DiaryNavigation.returnToObservation(
                    context,
                    widget.observation.id,
                  ),
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Torna al diario'),
          ),
        ),
    ],
  );
}

/// The list is updated from the current branch, never from the initial scope.
/// Pagination and a local search keep the complete checklist usable on a phone.
class RemainingCandidates extends StatefulWidget {
  const RemainingCandidates({
    super.key,
    required this.taxa,
    this.scope,
    this.observation,
    this.store,
    this.path,
    this.disabled = false,
    this.onBusy,
    this.onSaved,
    this.externalIds = const {},
    this.uncertainIds = const {},
  }) : assert((observation == null) == (store == null));
  final List<ItalicTaxon> taxa;
  final String? scope;
  final Observation? observation;
  final AppStore? store;
  final IdentificationPath Function()? path;
  final bool disabled;
  final ValueChanged<bool>? onBusy;
  final ValueChanged<IdentificationPath>? onSaved;
  final Set<int> externalIds, uncertainIds;
  @override
  State<RemainingCandidates> createState() => _RemainingCandidatesState();
}

class _RemainingCandidatesState extends State<RemainingCandidates> {
  final search = TextEditingController();
  int visible = 20;
  @override
  void didUpdateWidget(covariant RemainingCandidates oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope) {
      search.clear();
      visible = 20;
    }
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = search.text.trim().toLowerCase();
    final taxa =
        widget.taxa
            .where(
              (t) =>
                  query.isEmpty ||
                  t.scientificName.toLowerCase().contains(query) ||
                  t.italicId.toString() == query ||
                  t.synonyms.any((s) => s.toLowerCase().contains(query)),
            )
            .toList()
          ..sort((a, b) => a.scientificName.compareTo(b.scientificName));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 28),
        Text(
          'Specie rimaste (${widget.taxa.length})',
          key: const ValueKey('remaining-candidates-count'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Text(
          'La lista si aggiorna a ogni bivio. La scelta del nome è manuale e va verificata sul campione.',
        ),
        if (widget.taxa.length > 20 || query.isNotEmpty) ...[
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('remaining-candidates-search'),
            controller: search,
            enabled: !widget.disabled,
            decoration: const InputDecoration(
              labelText: 'Cerca tra le specie rimaste',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (_) => setState(() => visible = 20),
          ),
        ],
        if (taxa.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Nessuna specie rimasta per questa ricerca.'),
          ),
        for (final taxon in taxa.take(visible))
          Card(
            key: ValueKey('remaining-candidate-${taxon.italicId}'),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    taxon.scientificName,
                    style: const TextStyle(
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (widget.externalIds.contains(taxon.italicId))
                    const Text(
                      'Taxon della fonte esterno alla checklist locale.',
                    )
                  else ...[
                    if (widget.uncertainIds.contains(taxon.italicId))
                      const Text('Dati incompleti: candidato da verificare.'),
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
                    if (widget.observation != null && widget.path != null)
                      CandidateSelectionButton(
                        taxon: taxon,
                        observation: widget.observation!,
                        store: widget.store!,
                        path: widget.path!,
                        disabled: widget.disabled,
                        onBusy: widget.onBusy,
                        onSaved: widget.onSaved,
                      ),
                  ],
                ],
              ),
            ),
          ),
        if (taxa.length > visible)
          TextButton(
            onPressed: widget.disabled
                ? null
                : () => setState(() => visible += 20),
            child: Text('Mostra altre specie (${taxa.length - visible})'),
          ),
      ],
    );
  }
}
