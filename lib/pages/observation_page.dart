import 'package:flutter/material.dart';
import '../app_store.dart';
import '../models/observation.dart';
import '../widgets/photo_view.dart';
import 'determination_page.dart';
import 'observation_export_page.dart';

class ObservationPage extends StatefulWidget {
  const ObservationPage({
    super.key,
    required this.observation,
    required this.store,
  });
  final Observation observation;
  final AppStore store;

  @override
  State<ObservationPage> createState() => _ObservationPageState();
}

class _ObservationPageState extends State<ObservationPage> {
  late final TextEditingController notes;
  String? substrate;
  bool editing = false;

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
    notes = TextEditingController(text: widget.observation.notes);
    substrate = widget.observation.substrate;
  }

  @override
  void dispose() {
    notes.dispose();
    super.dispose();
  }

  Future<void> saveEdit() async {
    widget.observation.notes = notes.text.trim();
    widget.observation.substrate = substrate;
    await widget.store.save(widget.observation);
    if (mounted) setState(() => editing = false);
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
      await widget.store.delete(widget.observation);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.observation;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Osservazione'),
        actions: [
          IconButton(
            tooltip: editing
                ? 'Salva le modifiche prima di condividere'
                : 'Condividi risultati',
            onPressed: editing
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
            onPressed: editing
                ? saveEdit
                : () => setState(() => editing = true),
            icon: Icon(editing ? Icons.save : Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Elimina',
            onPressed: remove,
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
                '${o.latitude.toStringAsFixed(6)}, ${o.longitude.toStringAsFixed(6)}',
              ),
              info(
                Icons.gps_fixed,
                'Accuratezza GPS',
                '±${o.horizontalAccuracy.toStringAsFixed(1)} m',
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
                  'Misura della posizione',
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
                  onTap: () => _openDetermination(context),
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
          observation: widget.observation,
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
