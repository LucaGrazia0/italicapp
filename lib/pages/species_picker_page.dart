import 'package:flutter/material.dart';
import '../app_store.dart';
import '../data/italic_reference_repository.dart';
import '../models/observation.dart';
import '../services/manual_species.dart';

class SpeciesPickerPage extends StatefulWidget {
  const SpeciesPickerPage({super.key, this.selectedId, this.loadTaxa});
  final int? selectedId;
  final Future<List<ItalicTaxon>> Function()? loadTaxa;
  @override
  State<SpeciesPickerPage> createState() => _SpeciesPickerPageState();
}

class _SpeciesPickerPageState extends State<SpeciesPickerPage> {
  final search = TextEditingController();
  List<ItalicTaxon>? taxa;
  bool failed = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      failed = false;
      taxa = null;
    });
    try {
      final List<ItalicTaxon> rows;
      if (widget.loadTaxa != null) {
        rows = await widget.loadTaxa!();
      } else {
        final repo = ItalicReferenceRepository();
        await repo.load();
        rows = repo.taxa;
      }
      if (mounted) setState(() => taxa = rows);
    } catch (_) {
      if (mounted) setState(() => failed = true);
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
    final rows =
        taxa
            ?.where(
              (t) =>
                  query.isEmpty ||
                  t.scientificName.toLowerCase().contains(query) ||
                  t.synonyms.any((s) => s.toLowerCase().contains(query)) ||
                  t.italicId?.toString() == query,
            )
            .toList() ??
        [];
    return Scaffold(
      appBar: AppBar(title: const Text('Scegli specie')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: TextField(
                key: const ValueKey('species-picker-search'),
                controller: search,
                autocorrect: false,
                decoration: InputDecoration(
                  hintText: 'Nome, sinonimo o ID',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Cancella ricerca',
                          onPressed: () => setState(search.clear),
                          icon: const Icon(Icons.close),
                        ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            if (failed) ...[
              const Text('Lista non disponibile.'),
              TextButton(onPressed: _load, child: const Text('Riprova')),
            ] else if (taxa == null)
              const LinearProgressIndicator()
            else if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Nessuna specie trovata.'),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (_, i) {
                    final taxon = rows[i];
                    return ListTile(
                      key: ValueKey('pick-species-${taxon.italicId}'),
                      title: Text(taxon.scientificName),
                      trailing:
                          widget.selectedId != null &&
                              widget.selectedId == taxon.italicId
                          ? const Icon(Icons.check_circle)
                          : const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pop(context, taxon),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Select first, then persist a copy. Cancelling or a write failure leaves the
/// observation, its photo, position and saved key path untouched.
Future<Observation?> chooseObservationSpecies(
  BuildContext context, {
  required AppStore store,
  required Observation observation,
  Future<List<ItalicTaxon>> Function()? loadTaxa,
}) async {
  final taxon = await Navigator.push<ItalicTaxon>(
    context,
    MaterialPageRoute(
      builder: (_) => SpeciesPickerPage(
        selectedId: observation.taxonItalicId,
        loadTaxa: loadTaxa,
      ),
    ),
  );
  if (taxon == null || !context.mounted) return null;
  final updated = assignSpecies(observation, taxon);
  try {
    await store.save(updated);
    return updated;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Specie non salvata. Riprova.')),
      );
    }
    return null;
  }
}
