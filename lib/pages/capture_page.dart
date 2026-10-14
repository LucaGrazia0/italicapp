import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import '../app_store.dart';
import '../models/observation.dart';

class CapturePage extends StatefulWidget {
  const CapturePage({super.key, required this.store, required this.onSaved});
  final AppStore store;
  final VoidCallback onSaved;

  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> {
  final picker = ImagePicker();
  final notes = TextEditingController();
  Uint8List? photo;
  String? photoName;
  Position? position;
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

  Future<void> pickPhoto() async {
    setState(() { busy = true; error = null; });
    try {
      final x = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1800,
        imageQuality: 88,
      );
      if (x != null) {
        final bytes = await x.readAsBytes();
        setState(() { photo = bytes; photoName = x.name; });
      }
    } catch (e) {
      setState(() => error = 'Impossibile acquisire la foto: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> locate() async {
    setState(() { busy = true; error = null; });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Servizio di localizzazione non disponibile.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Permesso di localizzazione negato.');
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 20),
        ),
      );
      setState(() => position = p);
    } catch (e) {
      setState(() => error = 'Posizione non disponibile: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (photo == null || position == null) {
      setState(() => error = 'Servono almeno una foto e una posizione GPS.');
      return;
    }
    setState(() { busy = true; error = null; });
    final p = position!;
    final now = DateTime.now();
    final o = Observation(
      id: 'obs-${now.microsecondsSinceEpoch}',
      createdAt: now,
      latitude: p.latitude,
      longitude: p.longitude,
      horizontalAccuracy: p.accuracy,
      gpsAltitude: p.altitude,
      altitudeAccuracy: p.altitudeAccuracy,
      substrate: substrate,
      notes: notes.text.trim(),
      photoBytes: photo,
      photoName: photoName,
    );
    try {
      await widget.store.save(o);
      if (!mounted) return;
      setState(() {
        photo = null; photoName = null; position = null;
        substrate = null; notes.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Osservazione salvata nel database locale.')),
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
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Nuova osservazione',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('La foto e la posizione sono il nucleo dell’osservazione.'),
        const SizedBox(height: 20),
        AspectRatio(
          aspectRatio: 16/9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: photo == null
              ? Container(
                  color: const Color(0xFFE7EEE9),
                  child: const Center(child: Icon(Icons.camera_alt_outlined, size: 58)))
              : Image.memory(photo!, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: busy ? null : pickPhoto,
          icon: const Icon(Icons.camera_alt),
          label: Text(photo == null ? 'Scatta / scegli foto' : 'Cambia foto'),
        ),
        const SizedBox(height: 20),
        Card(
          child: ListTile(
            leading: const Icon(Icons.my_location),
            title: Text(position == null
              ? 'Posizione non acquisita'
              : '${position!.latitude.toStringAsFixed(6)}, ${position!.longitude.toStringAsFixed(6)}'),
            subtitle: position == null
              ? const Text('Acquisisci le coordinate dal dispositivo.')
              : Text('Accuratezza ±${position!.accuracy.toStringAsFixed(1)} m'
                  '${position!.altitude.isFinite ? ' • quota GPS ${position!.altitude.toStringAsFixed(1)} m' : ''}'),
            trailing: IconButton(
              tooltip: 'Acquisisci posizione',
              onPressed: busy ? null : locate,
              icon: const Icon(Icons.gps_fixed),
            ),
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: substrate,
          decoration: const InputDecoration(
            labelText: 'Substrato (facoltativo)',
            border: OutlineInputBorder(),
          ),
          items: substrates.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
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
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: busy ? null : save,
          icon: busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save_outlined),
          label: const Text('Salva osservazione'),
        ),
      ],
    );
  }
}
