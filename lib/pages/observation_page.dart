import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/services.dart';
import '../app_store.dart';
import '../models/observation.dart';
import '../widgets/photo_view.dart';
import 'determination_page.dart';
import 'observation_export_page.dart';
import 'map_location_page.dart';
import '../services/field_location.dart';
import '../services/diary_navigation.dart';

class ObservationPage extends StatefulWidget {
  static String routeName(String id) => DiaryNavigation.observationRoute(id);
  const ObservationPage({
    super.key,
    required this.observation,
    required this.store,
    this.mapBuilder,
    this.locationCapture,
  });
  final Observation observation;
  final AppStore store;
  final Widget Function(Observation)? mapBuilder;
  final Future<FieldFix> Function()? locationCapture;

  @override
  State<ObservationPage> createState() => _ObservationPageState();
}

class _ObservationPageState extends State<ObservationPage> {
  late final TextEditingController notes;
  String? substrate;
  bool editing = false;
  bool savingPosition = false;
  bool locating = false;
  int locationRequest = 0;
  String? positionError;
  late Observation observation;

  static const substrates = [
    'Roccia silicea',
    'Roccia calcarea',
    'Corteccia',
    'Legno',
    'Suolo',
    'Muschio',
    'Altro',
  ];

  @override
  void initState() {
    super.initState();
    observation = widget.observation;
    notes = TextEditingController(text: widget.observation.notes);
    substrate = widget.observation.substrate;
  }

  @override
  void dispose() {
    locationRequest++;
    if (locating) FieldLocation.cancel();
    notes.dispose();
    super.dispose();
  }

  Future<void> saveEdit() async {
    observation.notes = notes.text.trim();
    observation.substrate = substrate;
    await widget.store.save(observation);
    if (mounted) setState(() => editing = false);
  }

  Future<void> choosePosition() async {
    if (savingPosition || editing) return;
    final point = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            widget.mapBuilder?.call(observation) ??
            MapLocationPage(
              initialLatitude: observation.hasPosition
                  ? observation.latitude
                  : null,
              initialLongitude: observation.hasPosition
                  ? observation.longitude
                  : null,
            ),
      ),
    );
    if (!mounted || point == null) return;
    setState(() {
      savingPosition = true;
      positionError = null;
    });
    try {
      final updated = observation.withMapPosition(
        point.latitude,
        point.longitude,
      );
      await widget.store.save(updated);
      if (!mounted) return;
      setState(() => observation = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Posizione salvata nel diario. Disponibile anche offline.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Impossibile salvare la posizione. Il punto precedente è stato conservato. Riprova.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => savingPosition = false);
    }
  }

  Future<void> locate() async {
    if (savingPosition || editing) return;
    final request = ++locationRequest;
    setState(() {
      savingPosition = true;
      locating = true;
      positionError = null;
    });
    try {
      final fix = await (widget.locationCapture ?? FieldLocation.capture)();
      if (!mounted || request != locationRequest) return;
      setState(() => locating = false);
      final updated = fix.applyTo(observation);
      await widget.store.save(updated);
      if (!mounted || request != locationRequest) return;
      setState(() => observation = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Posizione GPS salvata nel diario.')),
      );
    } catch (e) {
      if (!mounted || request != locationRequest) return;
      setState(
        () => positionError = e is PlatformException
            ? '${e.message ?? "Misura GPS non disponibile."} Il punto precedente è stato conservato.'
            : 'Posizione GPS non salvata. Il punto precedente è stato conservato. $e',
      );
    } finally {
      if (mounted && request == locationRequest) {
        setState(() {
          savingPosition = false;
          locating = false;
        });
      }
    }
  }

  Future<void> cancelLocate() async {
    locationRequest++;
    setState(() {
      savingPosition = false;
      locating = false;
    });
    await FieldLocation.cancel();
  }

  Future<void> remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Eliminare osservazione?'),
        content: const Text(
          'Foto e dati locali di questa osservazione verranno eliminati.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.store.delete(observation);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = observation;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Osservazione'),
        actions: [
          IconButton(
            tooltip: editing
                ? 'Salva le modifiche prima di condividere'
                : 'Condividi risultati',
            onPressed: editing || savingPosition
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ObservationExportPage(observations: [o]),
                    ),
                  ),
            icon: const Icon(Icons.ios_share),
          ),
          IconButton(
            tooltip: editing ? 'Salva' : 'Modifica',
            onPressed: savingPosition
                ? null
                : editing
                ? saveEdit
                : () => setState(() => editing = true),
            icon: Icon(editing ? Icons.save : Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Elimina',
            onPressed: savingPosition ? null : remove,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (o.plotId != null && widget.store.plotById(o.plotId!) != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Plot · ${widget.store.plotById(o.plotId!)!.name}${!o.hasPosition && widget.store.plotById(o.plotId!)!.hasPosition ? ' · posizione disponibile nel plot' : ''}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              AspectRatio(
                aspectRatio: 16 / 10,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: ObservationPhoto(o),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                '${date(o.createdAt)} • ${two(o.createdAt.hour)}:${two(o.createdAt.minute)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Divider(height: 30),
              info(
                Icons.location_on_outlined,
                'Coordinate',
                o.hasPosition
                    ? '${o.latitude!.toStringAsFixed(6)}, ${o.longitude!.toStringAsFixed(6)}'
                    : 'Da aggiungere · puoi scegliere il punto sulla mappa online',
              ),
              if (o.hasPosition)
                info(
                  o.isMapPosition ? Icons.touch_app_outlined : Icons.gps_fixed,
                  o.isMapPosition
                      ? 'Origine della posizione'
                      : 'Accuratezza GPS',
                  o.positionLabel,
                ),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      key: const ValueKey('observation-gps'),
                      onPressed: editing || savingPosition ? null : locate,
                      icon: const Icon(Icons.gps_fixed),
                      label: const Text('Usa GPS'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('choose-map-position'),
                      onPressed: editing || savingPosition
                          ? null
                          : choosePosition,
                      icon: const Icon(Icons.add_location_alt_outlined),
                      label: Text(
                        savingPosition
                            ? 'Salvataggio…'
                            : o.hasPosition
                            ? 'Modifica mappa'
                            : 'Scegli mappa',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Il GPS registra dove ti trovi adesso. Sulla mappa online scegli il luogo del ritrovamento.',
              ),
              if (locating) ...[
                const LinearProgressIndicator(),
                const Text('Ricerca satelliti… fino a 35 secondi'),
                TextButton(
                  onPressed: cancelLocate,
                  child: const Text('Annulla misura GPS'),
                ),
              ],
              if (positionError != null)
                Text(
                  positionError!,
                  key: const ValueKey('observation-location-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              Text(
                o.isMapPosition
                    ? 'Punto scelto manualmente. La mappa non misura quota o precisione GPS.'
                    : o.hasPosition
                    ? 'La correzione manuale sostituisce le coordinate e rimuove quota e precisione della misura GPS precedente.'
                    : 'Puoi aggiungere la posizione anche dopo il salvataggio della foto.',
              ),
              info(
                Icons.landscape_outlined,
                'Quota sul livello del mare',
                o.seaLevelAltitude == null
                    ? 'Non disponibile · il rilievo non contiene una quota s.l.m. verificabile'
                    : '${o.seaLevelAltitude!.toStringAsFixed(1)} m s.l.m.',
              ),
              info(
                Icons.height,
                'Accuratezza quota s.l.m.',
                o.seaLevelAccuracy == null
                    ? 'Non disponibile'
                    : '±${o.seaLevelAccuracy!.toStringAsFixed(1)} m',
              ),
              if (o.gpsAltitude != null)
                info(
                  Icons.satellite_alt_outlined,
                  o.altitudeReference == null
                      ? 'Quota GPS originale · riferimento non dichiarato'
                      : 'Quota ellissoidica originale',
                  '${o.gpsAltitude!.toStringAsFixed(1)} m',
                ),
              if (o.positionMeasuredAt != null)
                info(
                  Icons.access_time,
                  o.isMapPosition
                      ? 'Punto scelto il'
                      : 'Misura della posizione',
                  o.positionMeasuredAt!.toLocal().toString(),
                ),
              if (o.satellitesUsed != null)
                info(
                  Icons.satellite_alt,
                  'Satelliti usati',
                  '${o.satellitesUsed}',
                ),
              if (o.positionMocked == true)
                const Text('Posizione simulata dal dispositivo.'),
              const SizedBox(height: 12),
              if (editing)
                DropdownButtonFormField<String>(
                  initialValue: substrate,
                  decoration: const InputDecoration(
                    labelText: 'Substrato',
                    border: OutlineInputBorder(),
                  ),
                  items: substrates
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => setState(() => substrate = v),
                )
              else
                info(
                  Icons.layers_outlined,
                  'Substrato',
                  o.substrate ?? 'Non indicato',
                ),
              const SizedBox(height: 12),
              if (editing)
                TextField(
                  controller: notes,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Note di campo',
                    border: OutlineInputBorder(),
                  ),
                )
              else
                info(
                  Icons.notes_outlined,
                  'Note',
                  o.notes.isEmpty ? 'Nessuna nota' : o.notes,
                ),
              const SizedBox(height: 22),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.science_outlined),
                  title: Text(o.taxonName ?? 'Non determinato'),
                  subtitle: Text(
                    o.identificationPath != null
                        ? 'Riprendi il percorso salvato · ${o.identificationPath!.answerCount} risposte'
                        : o.taxonName == null
                        ? 'Tocca per iniziare la determinazione'
                        : 'Tocca per rivedere la determinazione',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: savingPosition
                      ? null
                      : () => _openDetermination(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openDetermination(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DeterminationStartPage(
          observation: observation,
          store: widget.store,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Widget info(IconData icon, String title, String value) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(value),
  );
}

String two(int n) => n.toString().padLeft(2, '0');
String date(DateTime d) => '${two(d.day)}/${two(d.month)}/${d.year}';
