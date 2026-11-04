import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import '../app_store.dart';
import '../models/field_plot.dart';
import '../models/observation.dart';
import '../data/italic_reference_repository.dart';
import '../services/field_location.dart';
import '../services/plot_photos.dart';
import '../theme/app_theme.dart';
import '../widgets/photo_view.dart';
import 'map_location_page.dart';
import 'observation_page.dart';

String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

class PlotListSection extends StatelessWidget {
  const PlotListSection({super.key, required this.store});
  final AppStore store;
  Future<void> create(BuildContext context) async {
    final plot = await Navigator.push<FieldPlot>(
      context,
      MaterialPageRoute(builder: (_) => PlotFormPage(store: store)),
    );
    if (plot != null && context.mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlotPage(store: store, plotId: plot.id),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (store.plotLoadError != null)
        Card(
          child: ListTile(
            leading: const Icon(Icons.error_outline),
            title: Text(store.plotLoadError!),
            trailing: TextButton(
              onPressed: store.loadPlots,
              child: const Text('Riprova'),
            ),
          ),
        )
      else ...[
        FilledButton.icon(
          key: const ValueKey('new-plot'),
          onPressed: () => create(context),
          icon: const Icon(Icons.add),
          label: const Text('Nuovo plot'),
        ),
        const SizedBox(height: 14),
        if (store.plots.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    Icons.grid_view_rounded,
                    size: 42,
                    color: AppTheme.forest,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Il tuo primo plot',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Raccogli nello stesso rilievo una lista di specie, note e più foto da determinare.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        for (final plot in store.plots)
          Card(
            child: ListTile(
              key: ValueKey('plot-${plot.id}'),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              leading: const Icon(
                Icons.grid_view_rounded,
                color: AppTheme.forest,
              ),
              title: Text(
                plot.name,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                '${_date(plot.sampledAt)}${plot.areaM2 != null ? ' · ${plot.areaM2} m²' : ''}\n${store.speciesForPlot(plot).length} specie · ${store.photosForPlot(plot.id).length} foto',
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PlotPage(store: store, plotId: plot.id),
                ),
              ),
            ),
          ),
      ],
    ],
  );
}

class PlotFormPage extends StatefulWidget {
  const PlotFormPage({
    super.key,
    required this.store,
    this.plot,
    this.locationCapture,
    this.mapBuilder,
  });
  final AppStore store;
  final FieldPlot? plot;
  final Future<FieldFix> Function()? locationCapture;
  final Widget Function(double?, double?)? mapBuilder;
  @override
  State<PlotFormPage> createState() => _PlotFormPageState();
}

class _PlotFormPageState extends State<PlotFormPage> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.plot?.name ?? '');
  late final notes = TextEditingController(text: widget.plot?.notes ?? '');
  late final area = TextEditingController(
    text: widget.plot?.areaM2?.toString() ?? '',
  );
  late DateTime sampledAt = widget.plot?.sampledAt ?? DateTime.now();
  late Map<String, Object?> location = {
    for (final key in [
      'latitude',
      'longitude',
      'seaLevelAltitude',
      'horizontalAccuracy',
      'seaLevelAccuracy',
      'positionSource',
      'positionMeasuredAt',
      'altitudeReference',
    ])
      key: widget.plot?.toMap()[key],
  };
  bool busy = false, locating = false;
  String? error;
  int request = 0;
  @override
  void dispose() {
    request++;
    if (locating) FieldLocation.cancel();
    name.dispose();
    notes.dispose();
    area.dispose();
    super.dispose();
  }

  Future<void> locate() async {
    final ticket = ++request;
    setState(() {
      locating = true;
      error = null;
    });
    try {
      final fix = await (widget.locationCapture ?? FieldLocation.capture)();
      if (!mounted || ticket != request) return;
      setState(
        () => location = {
          'latitude': fix.latitude,
          'longitude': fix.longitude,
          'seaLevelAltitude': fix.seaLevelAltitude,
          'horizontalAccuracy': fix.accuracy,
          'seaLevelAccuracy': fix.altitudeAccuracy,
          'positionSource': fix.provider,
          'positionMeasuredAt': fix.timestamp.toIso8601String(),
          'altitudeReference': fix.altitudeSource,
        },
      );
    } catch (e) {
      if (mounted && ticket == request) {
        setState(
          () => error =
              'Posizione non acquisita. Puoi salvare il plot e aggiungerla in seguito.',
        );
      }
    } finally {
      if (mounted && ticket == request) setState(() => locating = false);
    }
  }

  Future<void> map() async {
    final point = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            widget.mapBuilder?.call(
              location['latitude'] as double?,
              location['longitude'] as double?,
            ) ??
            MapLocationPage(
              initialLatitude: location['latitude'] as double?,
              initialLongitude: location['longitude'] as double?,
            ),
      ),
    );
    if (point == null || !mounted) return;
    setState(
      () => location = {
        'latitude': point.latitude,
        'longitude': point.longitude,
        'seaLevelAltitude': null,
        'horizontalAccuracy': null,
        'seaLevelAccuracy': null,
        'positionSource': 'manual_map',
        'positionMeasuredAt': DateTime.now().toIso8601String(),
        'altitudeReference': null,
      },
    );
  }

  Future<void> save() async {
    if (busy || locating || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final now = DateTime.now();
      final plot = FieldPlot.fromMap({
        ...?widget.plot?.toMap(),
        'id': widget.plot?.id ?? 'plot-${now.microsecondsSinceEpoch}',
        'name': name.text.trim(),
        'createdAt':
            widget.plot?.createdAt.toIso8601String() ?? now.toIso8601String(),
        'sampledAt': sampledAt.toIso8601String(),
        'notes': notes.text.trim(),
        'areaM2': area.text.trim().isEmpty
            ? null
            : double.parse(area.text.trim().replaceAll(',', '.')),
        ...location,
      });
      await widget.store.savePlot(plot);
      if (mounted) Navigator.pop(context, plot);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Plot non salvato. I dati compilati restano qui: riprova.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.plot == null ? 'Nuovo plot' : 'Modifica plot'),
    ),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Un rilievo, tutte le tue specie',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppTheme.forest,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Compila il plot, poi aggiungi la lista delle specie e le foto. Potrai completarlo anche in seguito.',
          ),
          const SizedBox(height: 20),
          TextFormField(
            key: const ValueKey('plot-name'),
            controller: name,
            decoration: const InputDecoration(
              labelText: 'Nome del plot',
              hintText: 'Es. Bosco nord · plot 01',
            ),
            textCapitalization: TextCapitalization.sentences,
            validator: (value) => value?.trim().isNotEmpty == true
                ? null
                : 'Inserisci un nome per il plot.',
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            key: const ValueKey('plot-date'),
            onPressed: busy || locating
                ? null
                : () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: sampledAt,
                      firstDate: DateTime(1800),
                      lastDate: DateTime(2200),
                    );
                    if (date != null && mounted) {
                      setState(() => sampledAt = date);
                    }
                  },
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text('Data del rilievo · ${_date(sampledAt)}'),
          ),
          const SizedBox(height: 14),
          TextFormField(
            key: const ValueKey('plot-area'),
            controller: area,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Superficie in m² (facoltativa)',
            ),
            validator: (value) {
              if (value?.trim().isEmpty != false) return null;
              final n = double.tryParse(value!.replaceAll(',', '.'));
              return n != null && n.isFinite && n > 0
                  ? null
                  : 'Inserisci una superficie maggiore di zero.';
            },
          ),
          const SizedBox(height: 14),
          TextField(
            key: const ValueKey('plot-notes'),
            controller: notes,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Note del rilievo',
              hintText: 'Habitat, substrato, metodo, condizioni…',
            ),
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Posizione del plot',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    location['latitude'] == null
                        ? 'Puoi aggiungerla ora o in seguito.'
                        : '${(location['latitude'] as double).toStringAsFixed(5)}, ${(location['longitude'] as double).toStringAsFixed(5)}',
                  ),
                  if (location['seaLevelAltitude'] != null)
                    Text(
                      'Quota ${(location['seaLevelAltitude'] as double).toStringAsFixed(1)} m s.l.m.',
                    ),
                  if (location['positionSource'] == 'manual_map')
                    const Text(
                      'Punto scelto sulla mappa · quota non misurata.',
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        key: const ValueKey('plot-gps'),
                        onPressed: busy || locating ? null : locate,
                        icon: const Icon(Icons.gps_fixed),
                        label: const Text('Usa GPS'),
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('plot-map'),
                        onPressed: busy || locating ? null : map,
                        icon: const Icon(Icons.map_outlined),
                        label: const Text('Scegli sulla mappa'),
                      ),
                    ],
                  ),
                  if (locating) ...[
                    const SizedBox(height: 8),
                    const LinearProgressIndicator(),
                    TextButton(
                      onPressed: () async {
                        request++;
                        await FieldLocation.cancel();
                        if (mounted) setState(() => locating = false);
                      },
                      child: const Text('Annulla misura GPS'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('save-plot'),
            onPressed: busy || locating ? null : save,
            icon: const Icon(Icons.check),
            label: Text(busy ? 'Salvataggio…' : 'Salva plot'),
          ),
        ],
      ),
    ),
  );
}

class PlotPage extends StatefulWidget {
  const PlotPage({
    super.key,
    required this.store,
    required this.plotId,
    this.picker,
    this.loadTaxa,
    this.onOpenPhoto,
  });
  final AppStore store;
  final String plotId;
  final ImagePicker? picker;
  final Future<List<ItalicTaxon>> Function()? loadTaxa;
  final ValueChanged<Observation>? onOpenPhoto;
  @override
  State<PlotPage> createState() => _PlotPageState();
}

class _PlotPageState extends State<PlotPage> {
  bool busy = false;
  bool showPhotos = false;
  String? error;
  Future<void> species() async {
    final plot = widget.store.plotById(widget.plotId);
    if (plot == null) return;
    final selection = await Navigator.push<List<PlotSpecies>>(
      context,
      MaterialPageRoute(
        builder: (_) => PlotSpeciesPicker(
          initial: widget.store.speciesForPlot(plot),
          loadTaxa: widget.loadTaxa,
        ),
      ),
    );
    if (selection == null || !mounted) return;
    // Only explicitly added manual entries are pinned. Photo-derived species
    // remain live until the user edits their abundance/notes or adds them here.
    final existing = widget.store
        .speciesForPlot(plot)
        .map((s) => s.key)
        .toSet();
    final added = selection.where((s) => !existing.contains(s.key));
    await updateSpecies([...plot.species, ...added]);
  }

  Future<void> updateSpecies(List<PlotSpecies> entries) async {
    final current = widget.store.plotById(widget.plotId);
    if (current == null) return;
    setState(() => busy = true);
    try {
      await widget.store.savePlot(
        FieldPlot.fromMap({
          ...current.toMap(),
          'species': entries.map((s) => s.toMap()).toList(),
        }),
      );
      if (mounted) setState(() => error = null);
    } catch (_) {
      if (mounted) setState(() => error = 'Lista non salvata. Riprova.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> editSpecies(PlotSpecies species) async {
    final abundance = TextEditingController(text: species.abundance),
        notes = TextEditingController(text: species.notes);
    final route = DialogRoute<PlotSpecies>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(species.name),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const ValueKey('plot-species-abundance'),
                controller: abundance,
                decoration: const InputDecoration(
                  labelText: 'Copertura o abbondanza',
                  hintText: 'Es. 15% oppure 3 talli',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notes,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Note della specie',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              c,
              PlotSpecies(
                name: species.name,
                italicId: species.italicId,
                abundance: abundance.text.trim(),
                notes: notes.text.trim(),
              ),
            ),
            child: const Text('Salva'),
          ),
        ],
      ),
    );
    final changed = await Navigator.of(context).push(route);
    await route.completed;
    abundance.dispose();
    notes.dispose();
    if (changed == null || !mounted) return;
    final plot = widget.store.plotById(widget.plotId);
    if (plot == null) return;
    await updateSpecies([
      ...plot.species.where((s) => s.key != changed.key),
      changed,
    ]);
  }

  Future<void> removeSpecies(PlotSpecies species) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Togliere dalla lista manuale?'),
        content: Text(
          'Le foto associate restano nel plot. Se la specie è determinata in una foto, continuerà a comparire nella lista.\n\n${species.name}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Togli dalla lista'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final plot = widget.store.plotById(widget.plotId);
    if (plot != null) {
      await updateSpecies(
        plot.species.where((s) => s.key != species.key).toList(),
      );
    }
  }

  Future<void> photos({bool camera = false}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await PlotPhotos(
        widget.store,
        picker: widget.picker,
      ).add(widget.plotId, camera: camera);
      if (!mounted) return;
      if (result.failed > 0) {
        setState(
          () => error =
              'Salvate ${result.saved} foto; ${result.failed} non caricate. Puoi selezionare di nuovo quelle mancanti.',
        );
      }
      if (result.saved > 0 || result.skipped > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${result.saved} foto aggiunte${result.skipped > 0 ? ' · ${result.skipped} già presenti' : ''}. Tocca una foto per determinarla.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Foto non caricate. Controlla i permessi e riprova dalla galleria.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void openPhoto(Observation photo) {
    if (widget.onOpenPhoto != null) {
      widget.onOpenPhoto!(photo);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        settings: RouteSettings(name: ObservationPage.routeName(photo.id)),
        builder: (_) =>
            ObservationPage(observation: photo, store: widget.store),
      ),
    );
  }

  Future<void> copyList(FieldPlot plot, List<PlotSpecies> rows) async {
    await Clipboard.setData(
      ClipboardData(
        text: [
          plot.name,
          'Rilievo: ${_date(plot.sampledAt)}',
          if (plot.areaM2 != null) 'Superficie: ${plot.areaM2} m²',
          '',
          for (final s in rows)
            '${s.name}${s.abundance.isEmpty ? '' : ' · ${s.abundance}'}${s.notes.isEmpty ? '' : ' · ${s.notes}'}',
        ].join('\n'),
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lista delle specie copiata.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final plot = widget.store.plotById(widget.plotId);
      if (plot == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('Plot')),
          body: const Center(child: Text('Plot non disponibile.')),
        );
      }
      final rows = widget.store.speciesForPlot(plot),
          photos = widget.store.photosForPlot(plot.id);
      return Scaffold(
        appBar: AppBar(
          title: Text(plot.name),
          actions: [
            IconButton(
              key: const ValueKey('edit-plot'),
              tooltip: 'Modifica plot',
              onPressed: busy
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            PlotFormPage(store: widget.store, plot: plot),
                      ),
                    ),
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '${_date(plot.sampledAt)}${plot.areaM2 == null ? '' : ' · ${plot.areaM2} m²'}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (plot.hasPosition)
              Text(
                '${plot.latitude!.toStringAsFixed(5)}, ${plot.longitude!.toStringAsFixed(5)}${plot.seaLevelAltitude == null ? '' : ' · ${plot.seaLevelAltitude!.toStringAsFixed(1)} m s.l.m.'}',
              ),
            if (plot.notes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(plot.notes),
              ),
            const SizedBox(height: 20),
            SegmentedButton<bool>(
              key: const ValueKey('plot-sections'),
              segments: [
                ButtonSegment(
                  value: false,
                  icon: const Icon(Icons.checklist),
                  label: Text('Specie (${rows.length})'),
                ),
                ButtonSegment(
                  value: true,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text('Foto (${photos.length})'),
                ),
              ],
              selected: {showPhotos},
              onSelectionChanged: (value) =>
                  setState(() => showPhotos = value.single),
            ),
            const SizedBox(height: 16),
            if (!showPhotos) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Lista specie · ${rows.length}',
                      key: const ValueKey('plot-species-count'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.forest,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copia lista',
                    onPressed: rows.isEmpty ? null : () => copyList(plot, rows),
                    icon: const Icon(Icons.copy_outlined),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Aggiungi le specie dalla checklist o determina le foto. La lista si aggiorna dopo la scelta del candidato.',
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey('plot-add-species'),
                onPressed: busy ? null : species,
                icon: const Icon(Icons.playlist_add),
                label: const Text('Compila lista specie'),
              ),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Nessuna specie aggiunta. Puoi compilare la lista anche senza foto.',
                  ),
                ),
              for (final species in rows)
                Card(
                  child: ListTile(
                    key: ValueKey('plot-species-${species.key}'),
                    title: Text(
                      species.name,
                      style: const TextStyle(fontStyle: FontStyle.italic),
                    ),
                    subtitle: Text(
                      [
                        if (species.abundance.isNotEmpty) species.abundance,
                        if (species.notes.isNotEmpty) species.notes,
                        if (!plot.species.any((s) => s.key == species.key))
                          'Dalle foto determinate',
                      ].join('\n'),
                    ),
                    onTap: busy ? null : () => editSpecies(species),
                    trailing: plot.species.any((s) => s.key == species.key)
                        ? IconButton(
                            tooltip: 'Togli dalla lista manuale',
                            onPressed: busy
                                ? null
                                : () => removeSpecies(species),
                            icon: const Icon(Icons.remove_circle_outline),
                          )
                        : const Icon(Icons.photo_outlined),
                  ),
                ),
            ],
            if (showPhotos) ...[
              const SizedBox(height: 8),
              Text(
                'Foto del plot · ${photos.length}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppTheme.forest,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Importa più immagini dalla galleria oppure scatta una foto. Apri ciascuna immagine e usa le chiavi per scegliere la specie.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('plot-add-photos'),
                    onPressed: busy ? null : () => this.photos(),
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('Aggiungi foto'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('plot-take-photo'),
                    onPressed: busy ? null : () => this.photos(camera: true),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Scatta foto'),
                  ),
                ],
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: LinearProgressIndicator(),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              if (photos.isEmpty)
                const Text(
                  'Le foto che aggiungi qui restano associate a questo plot.',
                ),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: photos.length,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 240,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: .85,
                ),
                itemBuilder: (_, i) {
                  final photo = photos[i];
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      key: ValueKey('plot-photo-${photo.id}'),
                      onTap: () => openPhoto(photo),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: ObservationPhoto(photo)),
                          Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  photo.taxonName ?? 'Da determinare',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Apri foto e chiavi',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.forest,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      );
    },
  );
}

class PlotSpeciesPicker extends StatefulWidget {
  const PlotSpeciesPicker({super.key, required this.initial, this.loadTaxa});
  final List<PlotSpecies> initial;
  final Future<List<ItalicTaxon>> Function()? loadTaxa;
  @override
  State<PlotSpeciesPicker> createState() => _PlotSpeciesPickerState();
}

class _PlotSpeciesPickerState extends State<PlotSpeciesPicker> {
  late Future<List<ItalicTaxon>> loading;
  late final selected = {for (final s in widget.initial) s.key: s};
  String query = '';
  static Future<List<ItalicTaxon>> load() async {
    final repo = ItalicReferenceRepository();
    await repo.load();
    return repo.taxa;
  }

  @override
  void initState() {
    super.initState();
    loading = (widget.loadTaxa ?? load)();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Aggiungi specie')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: TextField(
            key: const ValueKey('plot-species-search'),
            decoration: const InputDecoration(
              labelText: 'Cerca nella checklist',
              hintText: 'Nome scientifico o sinonimo',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => query = v.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<ItalicTaxon>>(
            future: loading,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: TextButton(
                    onPressed: () => setState(() {
                      loading = (widget.loadTaxa ?? load)();
                    }),
                    child: const Text('Checklist non disponibile · riprova'),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final matches = snapshot.data!
                  .where(
                    (t) =>
                        query.isEmpty ||
                        t.scientificName.toLowerCase().contains(query) ||
                        t.synonyms.any((s) => s.toLowerCase().contains(query)),
                  )
                  .take(80)
                  .toList();
              if (matches.isEmpty) {
                return const Center(child: Text('Nessuna specie trovata.'));
              }
              return ListView.builder(
                itemCount: matches.length,
                itemBuilder: (_, i) {
                  final taxon = matches[i],
                      species = PlotSpecies(
                        name: taxon.scientificName,
                        italicId: taxon.italicId,
                      );
                  final exists = widget.initial.any(
                    (s) => s.key == species.key,
                  );
                  return CheckboxListTile(
                    key: ValueKey(
                      'select-plot-species-${taxon.italicId ?? species.key}',
                    ),
                    title: Text(taxon.scientificName),
                    subtitle: exists
                        ? const Text('Già nella lista del plot')
                        : null,
                    value: selected.containsKey(species.key),
                    onChanged: exists
                        ? null
                        : (value) => setState(() {
                            if (value == true) {
                              selected[species.key] = species;
                            } else {
                              selected.remove(species.key);
                            }
                          }),
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey('confirm-plot-species'),
                onPressed: () =>
                    Navigator.pop(context, selected.values.toList()),
                icon: const Icon(Icons.check),
                label: Text('Conferma lista · ${selected.length} specie'),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
