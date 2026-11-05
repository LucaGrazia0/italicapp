import 'package:flutter/material.dart';
import '../app_store.dart';
import '../data/italic_reference_repository.dart';
import '../models/observation.dart';

IdentificationRank manualNameRank(String value) {
  if (RegExp(
    r'\b(?:cf|cfr|aff|sp|spp|agg|indet)\b|\?',
    caseSensitive: false,
  ).hasMatch(value)) {
    return IdentificationRank.undetermined;
  }
  if (RegExp(
    r'^[A-ZÀ-ÖØ-Þ][a-zà-öø-ÿ-]+\s+[a-zà-öø-ÿ-]+(?:\s|$)',
  ).hasMatch(value)) {
    return IdentificationRank.species;
  }
  if (RegExp(r'^[A-ZÀ-ÖØ-Þ][a-zà-öø-ÿ-]+$').hasMatch(value)) {
    return value.endsWith('aceae')
        ? IdentificationRank.family
        : IdentificationRank.genus;
  }
  return IdentificationRank.undetermined;
}

class SpeciesNamePage extends StatefulWidget {
  const SpeciesNamePage({
    super.key,
    required this.store,
    required this.observation,
    this.loadTaxa,
  });
  final AppStore store;
  final Observation observation;
  final Future<List<ItalicTaxon>> Function()? loadTaxa;
  @override
  State<SpeciesNamePage> createState() => _SpeciesNamePageState();
}

class _SpeciesNamePageState extends State<SpeciesNamePage> {
  late final name = TextEditingController(
    text: widget.observation.taxonName ?? '',
  );
  List<ItalicTaxon> taxa = [];
  ItalicTaxon? selected;
  bool loading = true, busy = false;
  String? error, catalogueError;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final List<ItalicTaxon> rows;
      if (widget.loadTaxa != null) {
        rows = await widget.loadTaxa!();
      } else {
        final repo = ItalicReferenceRepository();
        await repo.load();
        rows = repo.taxa;
      }
      if (mounted) {
        setState(() {
          taxa = rows;
          catalogueError = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => catalogueError =
              'Suggerimenti non disponibili. Puoi comunque salvare il nome scritto.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  ItalicTaxon? exactTaxon(String input) {
    if (selected != null && selected!.scientificName == input) return selected;
    final normalized = input.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final matches = taxa
        .where(
          (t) =>
              t.scientificName.toLowerCase() == normalized ||
              RegExp(
                    r'^[^ ]+ [^ ]+',
                  ).firstMatch(t.scientificName.toLowerCase())?.group(0) ==
                  normalized,
        )
        .toList();
    return matches.length == 1 ? matches.single : null;
  }

  Future<void> save() async {
    final input = name.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (input.isEmpty) {
      setState(() => error = 'Scrivi il nome da salvare.');
      return;
    }
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    final taxon = exactTaxon(input);
    final updated = Observation.fromMap(widget.observation.toMap())
      ..taxonName = taxon?.scientificName ?? input
      ..taxonItalicId = taxon?.italicId
      ..rank = manualNameRank(taxon?.scientificName ?? input)
      ..identificationMethod = 'manual';
    try {
      await widget.store.save(updated);
      final original = widget.observation;
      original
        ..taxonName = updated.taxonName
        ..taxonItalicId = updated.taxonItalicId
        ..rank = updated.rank
        ..identificationMethod = 'manual';
      if (mounted) Navigator.pop(context, updated);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Nome non salvato. I dati precedenti restano conservati. Riprova.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = name.text.trim().toLowerCase();
    final suggestions = query.length < 2
        ? <ItalicTaxon>[]
        : taxa
              .where(
                (t) =>
                    t.scientificName.toLowerCase().contains(query) ||
                    t.synonyms.any((s) => s.toLowerCase().contains(query)),
              )
              .take(25)
              .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Scrivi nome della specie')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Puoi assegnare il nome direttamente, senza seguire la chiave. Scegli un suggerimento della checklist oppure conserva il testo libero. Le determinazioni personali restano da verificare.',
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('manual-species-name'),
            controller: name,
            enabled: !busy,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Nome scientifico',
              hintText: 'Es. Physcia adscendens',
              prefixIcon: Icon(Icons.edit_note),
            ),
            onChanged: (_) => setState(() => selected = null),
          ),
          if (widget.observation.identificationPath != null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'Il percorso precedente resta disponibile come storico: il nome scritto manualmente non viene attribuito a quel percorso.',
              ),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('save-manual-species'),
            onPressed: busy ? null : save,
            icon: const Icon(Icons.save_outlined),
            label: Text(busy ? 'Salvataggio…' : 'Salva nome nel diario'),
          ),
          if (loading) const LinearProgressIndicator(),
          if (catalogueError != null)
            TextButton(onPressed: load, child: Text(catalogueError!)),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Suggerimenti dalla checklist'),
            for (final t in suggestions)
              ListTile(
                key: ValueKey('manual-taxon-${t.italicId}'),
                title: Text(t.scientificName),
                trailing: selected?.italicId == t.italicId
                    ? const Icon(Icons.check_circle)
                    : const Icon(Icons.north_west),
                onTap: busy
                    ? null
                    : () => setState(() {
                        selected = t;
                        name.text = t.scientificName;
                      }),
              ),
          ],
        ],
      ),
    );
  }
}
