import 'package:flutter/material.dart';
import '../app_store.dart';
import '../services/diary_filter.dart';
import '../pages/area_filter_page.dart';

class DiaryFilters extends StatefulWidget {
  const DiaryFilters({super.key, required this.store});
  final AppStore store;
  @override
  State<DiaryFilters> createState() => _DiaryFiltersState();
}

class _DiaryFiltersState extends State<DiaryFilters> {
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (widget.store.regions != null) return;
    try {
      await widget.store.loadRegions();
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Regioni non disponibili. Tocca per riprovare.');
      }
    }
  }

  Future<void> edit() async {
    if (error != null) {
      setState(() => error = null);
      await load();
    }
    if (!mounted) return;
    final result = await Navigator.push<DiaryFilter>(
      context,
      MaterialPageRoute(builder: (_) => _FilterPage(store: widget.store)),
    );
    if (result != null) widget.store.setDiaryFilter(result);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final f = widget.store.diaryFilter;
      return Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            key: const ValueKey('diary-filters'),
            onPressed: edit,
            icon: Icon(f.active ? Icons.filter_alt : Icons.filter_alt_outlined),
            label: Text(
              error ?? (f.active ? 'Filtri attivi' : 'Filtra diario'),
            ),
          ),
          if (f.active)
            TextButton(
              onPressed: () => widget.store.setDiaryFilter(const DiaryFilter()),
              child: const Text('Azzera'),
            ),
          if (f.active)
            Text(
              '${widget.store.filteredObservations.length} foto · ${widget.store.filteredPlots.length} plot',
            ),
        ],
      );
    },
  );
}

class _FilterPage extends StatefulWidget {
  const _FilterPage({required this.store});
  final AppStore store;
  @override
  State<_FilterPage> createState() => _FilterPageState();
}

class _FilterPageState extends State<_FilterPage> {
  late DateTime? from = widget.store.diaryFilter.from,
      to = widget.store.diaryFilter.to;
  late String? region = widget.store.diaryFilter.regionId;
  late GeoRectangle? area = widget.store.diaryFilter.rectangle;
  String date(DateTime? d) =>
      d == null ? 'Qualsiasi' : '${d.day}/${d.month}/${d.year}';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Filtra il diario')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'I filtri valgono per diario, mappa ed esportazione. Per i plot usiamo data e posizione del rilievo; per i ritrovamenti singoli quelle della foto. Senza posizione un record non rientra in un’area geografica.',
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () async {
            final d = await showDateRangePicker(
              context: context,
              firstDate: DateTime(1800),
              lastDate: DateTime(2200),
              initialDateRange: from == null || to == null
                  ? null
                  : DateTimeRange(start: from!, end: to!),
            );
            if (d != null) {
              setState(() {
                from = d.start;
                to = d.end;
              });
            }
          },
          icon: const Icon(Icons.date_range),
          label: Text('Data: ${date(from)} – ${date(to)}'),
        ),
        TextButton(
          onPressed: () => setState(() {
            from = null;
            to = null;
          }),
          child: const Text('Tutte le date'),
        ),
        DropdownButtonFormField<String>(
          initialValue: region ?? '',
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Regione italiana'),
          items: [
            const DropdownMenuItem(value: '', child: Text('Tutte le regioni')),
            for (final r in widget.store.regions?.regions ?? <ItalianRegion>[])
              DropdownMenuItem(value: r.id, child: Text(r.name)),
            const DropdownMenuItem(
              value: 'unknown',
              child: Text('Senza regione italiana nota'),
            ),
          ],
          onChanged: widget.store.regions == null
              ? null
              : (v) => setState(() => region = v == '' ? null : v),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () async {
            final r = await Navigator.push<GeoRectangle>(
              context,
              MaterialPageRoute(builder: (_) => AreaFilterPage(initial: area)),
            );
            if (r != null) setState(() => area = r);
          },
          icon: const Icon(Icons.crop_free),
          label: Text(
            area == null
                ? 'Scegli rettangolo sulla mappa'
                : 'Modifica rettangolo selezionato',
          ),
        ),
        if (area != null) ...[
          Text(
            '${area!.south.toStringAsFixed(4)}, ${area!.west.toStringAsFixed(4)} → ${area!.north.toStringAsFixed(4)}, ${area!.east.toStringAsFixed(4)}',
          ),
          TextButton(
            onPressed: () => setState(() => area = null),
            child: const Text('Rimuovi area'),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton(
          key: const ValueKey('apply-diary-filters'),
          onPressed: () => Navigator.pop(
            context,
            DiaryFilter(from: from, to: to, regionId: region, rectangle: area),
          ),
          child: const Text('Applica filtri'),
        ),
        const SizedBox(height: 16),
        const Text(
          'Regioni: Istat, confini generalizzati 2026 · CC BY 4.0. L’attribuzione geografica è indicativa vicino ai confini e viene calcolata sul dispositivo.',
        ),
      ],
    ),
  );
}
