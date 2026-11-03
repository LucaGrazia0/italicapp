import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import '../app_store.dart';
import '../models/observation.dart';
import '../services/field_location.dart';
import 'package:flutter/services.dart';
import 'map_location_page.dart';

class CapturePage extends StatefulWidget {
  const CapturePage({
    super.key,
    required this.store,
    required this.onSaved,
    this.picker,
    this.mapBuilder,
    this.locationCapture,
  });
  final AppStore store;
  final VoidCallback onSaved;
  final ImagePicker? picker;
  final Widget Function(double?, double?)? mapBuilder;
  final Future<FieldFix> Function()? locationCapture;

  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> {
  late final picker = widget.picker ?? ImagePicker();
  final notes = TextEditingController();
  Uint8List? photo;
  String? photoName;
  FieldFix? position;
  LatLng? mapPoint;
  DateTime? mapSelectedAt;
  int locationRequest = 0;
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
    final request = ++locationRequest;
    setState(() {
      busy = true;
      locating = true;
      error = null;
    });
    try {
      final fix = await (widget.locationCapture ?? FieldLocation.capture)();
      if (mounted && request == locationRequest) {
        setState(() {
          position = fix;
          mapPoint = null;
          mapSelectedAt = null;
        });
      }
    } catch (e) {
      if (mounted && request == locationRequest) {
        setState(
          () => error = e is PlatformException
              ? (e.message ?? 'Misura GPS non disponibile.')
              : 'Posizione non disponibile: $e',
        );
      }
    } finally {
      if (mounted && request == locationRequest) {
        setState(() {
          busy = false;
          locating = false;
        });
      }
    }
  }

  Future<void> cancelLocate() async {
    locationRequest++;
    setState(() {
      busy = false;
      locating = false;
    });
    await FieldLocation.cancel();
  }

  Future<void> chooseMap() async {
    if (busy) return;
    final lat = mapPoint?.latitude ?? position?.latitude;
    final lon = mapPoint?.longitude ?? position?.longitude;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final point = await Navigator.push<LatLng>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              widget.mapBuilder?.call(lat, lon) ??
              MapLocationPage(initialLatitude: lat, initialLongitude: lon),
        ),
      );
      if (mounted && point != null) {
        setState(() {
          mapPoint = point;
          mapSelectedAt = DateTime.now();
          position = null;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (photo == null) {
      setState(() => error = 'Aggiungi una foto per salvare l’osservazione.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    final now = DateTime.now();
    final base = Observation(
      id: 'obs-${now.microsecondsSinceEpoch}',
      createdAt: now,
      substrate: substrate,
      notes: notes.text.trim(),
      photoBytes: photo,
      photoName: photoName,
    );
    final o = mapPoint != null
        ? base.withMapPosition(
            mapPoint!.latitude,
            mapPoint!.longitude,
            selectedAt: mapSelectedAt,
          )
        : position?.applyTo(base) ?? base;
    try {
      await widget.store.save(o);
      if (!mounted) return;
      setState(() {
        photo = null;
        photoName = null;
        position = null;
        mapPoint = null;
        mapSelectedAt = null;
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
      if (mounted) setState(() => error = 'Errore durante il salvataggio: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    locationRequest++;
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
        const Text(
          'Aggiungi la foto e scegli la posizione con il GPS o sulla mappa. Puoi farlo anche in seguito dal diario.',
        ),
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
                  : mapPoint != null
                  ? '${mapPoint!.latitude.toStringAsFixed(6)}, ${mapPoint!.longitude.toStringAsFixed(6)}'
                  : position == null
                  ? 'Posizione non acquisita'
                  : '${position!.latitude.toStringAsFixed(6)}, ${position!.longitude.toStringAsFixed(6)}',
            ),
            subtitle: mapPoint != null
                ? const Text(
                    'Punto scelto sulla mappa · quota e precisione GPS non misurate.',
                  )
                : position == null
                ? const Text(
                    'GPS facoltativo. Puoi salvare ora e scegliere il punto sulla mappa dal diario quando hai internet. La quota GPS, se disponibile, è riferita al livello del mare.',
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
          ),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            Tooltip(
              message: position == null
                  ? 'Acquisisci posizione'
                  : 'Aggiorna posizione',
              child: FilledButton.icon(
                key: const ValueKey('capture-gps'),
                onPressed: busy ? null : locate,
                icon: const Icon(Icons.gps_fixed),
                label: const Text('Usa GPS'),
              ),
            ),
            OutlinedButton.icon(
              key: const ValueKey('capture-map'),
              onPressed: busy ? null : chooseMap,
              icon: const Icon(Icons.map_outlined),
              label: const Text('Scegli sulla mappa · online'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Il GPS registra dove ti trovi adesso. Sulla mappa scegli il luogo del ritrovamento.',
        ),
        if (locating) ...[
          const LinearProgressIndicator(),
          TextButton(
            onPressed: cancelLocate,
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
