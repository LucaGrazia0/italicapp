import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import '../app_store.dart';
import '../models/observation.dart';
import '../services/field_location.dart';
import 'package:flutter/services.dart';

class CapturePage extends StatefulWidget {
  const CapturePage({
    super.key,
    required this.store,
    required this.onSaved,
    this.picker,
  });
  final AppStore store;
  final VoidCallback onSaved;
  final ImagePicker? picker;

  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> {
  late final picker = widget.picker ?? ImagePicker();
  final notes = TextEditingController();
  Uint8List? photo;
  String? photoName;
  FieldFix? position;
  bool locating = false;
  String? substrate;
  bool busy = false;
  String? error;

  final substrates = const [
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
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _recoverPhoto();
    }
  }

  Future<void> _loadPhoto(XFile file) async {
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) throw StateError('Il file selezionato è vuoto.');
    if (!mounted) return;
    setState(() {
      photo = bytes;
      photoName = file.name;
    });
  }

  Future<void> _recoverPhoto() async {
    setState(() => busy = true);
    try {
      final response = await picker.retrieveLostData();
      if (response.isEmpty || !mounted) return;
      final files = response.files;
      if (files != null && files.isNotEmpty) {
        await _loadPhoto(files.first);
      } else if (response.exception != null) {
        setState(
          () => error =
              'Non è stato possibile recuperare la foto. Selezionala di nuovo dalla galleria.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Recupero foto non disponibile. Puoi selezionare nuovamente la foto.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pickPhoto(ImageSource source) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final x = await picker.pickImage(
        source: source,
        maxWidth: 1800,
        imageQuality: 88,
        requestFullMetadata: false,
      );
      if (x != null) {
        await _loadPhoto(x);
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error =
              'Impossibile caricare la foto. Riprova e verifica i permessi per ${source == ImageSource.gallery ? "le foto" : "la fotocamera"}.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> locate() async {
    if (busy) return;
    setState(() {
      busy = true;
      locating = true;
      error = null;
    });
    try {
      final fix = await FieldLocation.capture();
      if (mounted) setState(() => position = fix);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is PlatformException
              ? (e.message ?? 'Misura GPS non disponibile.')
              : 'Posizione non disponibile: $e',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          locating = false;
        });
      }
    }
  }

  Future<void> save() async {
    if (photo == null || position == null) {
      setState(() => error = 'Servono almeno una foto e una posizione GPS.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    final p = position!;
    final now = DateTime.now();
    final o = Observation(
      id: 'obs-${now.microsecondsSinceEpoch}',
      createdAt: now,
      latitude: p.latitude,
      longitude: p.longitude,
      horizontalAccuracy: p.accuracy,
      gpsAltitude: p.ellipsoidAltitude,
      altitudeAccuracy: null,
      seaLevelAltitude: p.seaLevelAltitude,
      seaLevelAccuracy: p.altitudeAccuracy,
      altitudeReference: p.altitudeSource,
      positionMeasuredAt: p.timestamp,
      positionProvider: p.provider,
      satellitesUsed: p.satellitesUsed,
      positionMocked: p.mocked,
      substrate: substrate,
      notes: notes.text.trim(),
      photoBytes: photo,
      photoName: photoName,
    );
    try {
      await widget.store.save(o);
      if (!mounted) return;
      setState(() {
        photo = null;
        photoName = null;
        position = null;
        substrate = null;
        notes.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Osservazione salvata nel database locale.'),
        ),
      );
      widget.onSaved();
    } catch (e) {
      setState(() => error = 'Errore durante il salvataggio: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    if (locating) FieldLocation.cancel();
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Nuova osservazione',
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text('La foto e la posizione sono il nucleo dell’osservazione.'),
        const SizedBox(height: 20),
        AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: photo == null
                ? Container(
                    color: const Color(0xFFE7EEE9),
                    child: const Center(
                      child: Icon(Icons.camera_alt_outlined, size: 58),
                    ),
                  )
                : Image.memory(photo!, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              key: const ValueKey('capture-camera'),
              onPressed: busy ? null : () => pickPhoto(ImageSource.camera),
              icon: const Icon(Icons.camera_alt),
              label: const Text('Scatta foto'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('capture-gallery'),
              onPressed: busy ? null : () => pickPhoto(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Scegli dalla galleria'),
            ),
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 20),
        Card(
          child: ListTile(
            leading: const Icon(Icons.my_location),
            title: Text(
              locating
                  ? 'Ricerca satelliti… fino a 35 secondi'
                  : position == null
                  ? 'Posizione non acquisita'
                  : '${position!.latitude.toStringAsFixed(6)}, ${position!.longitude.toStringAsFixed(6)}',
            ),
            subtitle: position == null
                ? const Text(
                    'Misura all’aperto per una migliore precisione. La quota viene riferita al livello del mare.',
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Accuratezza posizione ±${position!.accuracy.toStringAsFixed(1)} m',
                      ),
                      Text(
                        position!.seaLevelAltitude == null
                            ? 'Quota s.l.m. non disponibile'
                            : 'Quota ${position!.seaLevelAltitude!.toStringAsFixed(1)} m s.l.m.${position!.altitudeAccuracy == null ? " · accuratezza quota non disponibile" : " · ±${position!.altitudeAccuracy!.toStringAsFixed(1)} m"}',
                      ),
                      if (position!.satellitesUsed != null)
                        Text('Satelliti usati: ${position!.satellitesUsed}'),
                      if (!position!.precise)
                        const Text(
                          'Precisione limitata: prova ad aggiornare la misura all’aperto.',
                        ),
                      if (position!.mocked)
                        const Text('Posizione simulata dal dispositivo.'),
                    ],
                  ),
            trailing: IconButton(
              tooltip: position == null
                  ? 'Acquisisci posizione'
                  : 'Aggiorna posizione',
              onPressed: busy ? null : locate,
              icon: const Icon(Icons.gps_fixed),
            ),
          ),
        ),
        if (locating) ...[
          const LinearProgressIndicator(),
          TextButton(
            onPressed: FieldLocation.cancel,
            child: const Text('Annulla misura GPS'),
          ),
        ],
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: substrate,
          decoration: const InputDecoration(
            labelText: 'Substrato (facoltativo)',
            border: OutlineInputBorder(),
          ),
          items: substrates
              .map((s) => DropdownMenuItem(value: s, child: Text(s)))
              .toList(),
          onChanged: (v) => setState(() => substrate = v),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: notes,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Note di campo',
            border: OutlineInputBorder(),
            hintText: 'Habitat, esposizione, abbondanza, osservazioni…',
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: busy ? null : save,
          icon: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: const Text('Salva osservazione'),
        ),
      ],
    );
  }
}
