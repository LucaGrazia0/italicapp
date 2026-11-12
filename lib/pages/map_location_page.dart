import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../widgets/map_tools.dart';
import '../models/map_position.dart';

import '../services/online_map.dart';

class MapLocationPage extends StatefulWidget {
  const MapLocationPage({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    this.initialUncertaintyInMeters,
    this.onlineMap,
    this.tileProvider,
  });

  final double? initialLatitude, initialLongitude;
  final double? initialUncertaintyInMeters;
  final OnlineMap? onlineMap;
  final TileProvider? tileProvider;

  @override
  State<MapLocationPage> createState() => _MapLocationPageState();
}

class _MapLocationPageState extends State<MapLocationPage> {
  final controller = MapController();
  late final uncertainty = TextEditingController(
    text: MapPosition.validUncertainty(widget.initialUncertaintyInMeters)
        ? widget.initialUncertaintyInMeters?.toString() ?? ''
        : '',
  );
  double? get uncertaintyValue =>
      double.tryParse(uncertainty.text.trim().replaceAll(',', '.'));
  String? get uncertaintyError {
    if (uncertainty.text.trim().isEmpty) return null;
    if (uncertaintyValue == null ||
        !MapPosition.validUncertainty(uncertaintyValue)) {
      return 'Inserisci un numero maggiore di 0, fino a 20.000.000 m.';
    }
    return null;
  }

  late final onlineMap = widget.onlineMap ?? OnlineMap();
  late TileProvider tileProvider;
  late final hasInitial =
      widget.initialLatitude != null && widget.initialLongitude != null;
  late final initial = hasInitial
      ? LatLng(
          widget.initialLatitude!.clamp(-85.05112878, 85.05112878),
          widget.initialLongitude!,
        )
      : const LatLng(42.5, 12.5);
  late final zoom = hasInitial ? 15.0 : 5.0;
  LatLng? selected, searchCenter;
  MapBaseLayer layer = MapBaseLayer.street;
  bool checking = true;
  bool available = false;
  bool mapReady = false;
  int generation = 0;
  String? error;

  @override
  void initState() {
    super.initState();
    tileProvider = _createTileProvider();
    _check();
  }

  TileProvider _createTileProvider() =>
      widget.tileProvider ??
      NetworkTileProvider(
        headers: kIsWeb ? {} : {'User-Agent': OnlineMap.userAgent},
      );

  Future<void> _check({bool confirm = false}) async {
    if (confirm && uncertaintyError != null) return;
    final point = confirm && selected != null
        ? selected!
        : (mapReady ? controller.camera.center : (searchCenter ?? initial));
    final currentZoom = mapReady ? controller.camera.zoom : zoom;
    setState(() {
      checking = true;
      error = null;
    });
    try {
      if (layer == MapBaseLayer.street) {
        await onlineMap.check(
          point.latitude,
          point.longitude,
          currentZoom.floor(),
        );
      } else {
        await onlineMap.checkSource(
          point.latitude,
          point.longitude,
          currentZoom.floor(),
          template: layer.template,
        );
      }
      if (!mounted) return;
      if (confirm && selected != null) {
        Navigator.pop(
          context,
          MapPosition(
            selected!.latitude,
            selected!.longitude,
            uncertaintyInMeters: uncertaintyValue,
          ),
        );
        return;
      }
      setState(() {
        available = true;
        checking = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        available = false;
        checking = false;
        error =
            'La mappa richiede una connessione internet. Controlla la rete e riprova. Il diario resta salvato sul dispositivo.';
      });
    }
  }

  void _tileFailed() {
    // Image callbacks can run during a frame; avoid changing the widget tree then.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || error != null) return;
      setState(() {
        available = false;
        error =
            'Alcune parti della mappa non si caricano. Controlla la connessione e riprova prima di confermare il punto.';
      });
    });
  }

  void _retry() {
    // Recreate failed tile requests, preserving the marker and the camera.
    if (!mapReady) tileProvider.dispose();
    setState(() {
      generation++;
      tileProvider = _createTileProvider();
    });
    _check();
  }

  @override
  void dispose() {
    onlineMap.close();
    if (!mapReady) tileProvider.dispose();
    controller.dispose();
    uncertainty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    resizeToAvoidBottomInset: false,
    appBar: AppBar(title: const Text('Scegli il punto sulla mappa')),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              key: const ValueKey('map-position-uncertainty'),
              controller: uncertainty,
              readOnly: checking,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Incertezza del punto (m)',
                hintText: 'Es. 25',
                helperText:
                    'Raggio stimato attorno al punto. Se non lo sai, lascia vuoto.',
                helperMaxLines: 2,
                errorText: uncertaintyError,
                errorMaxLines: 2,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: MapTools(
              layer: layer,
              enabled: !checking,
              onLayer: (v) {
                setState(() {
                  layer = v;
                  error = null;
                });
                _check();
              },
              onPlace: (p) {
                setState(() => searchCenter = p.point);
                if (mapReady) focusPlace(controller, p);
                _check();
              },
            ),
          ),

          const Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Text(
              'Mappa online · ingrandisci e tocca il luogo del ritrovamento. Il punto verrà salvato nel diario anche per l’uso offline.',
            ),
          ),
          if (checking) const LinearProgressIndicator(),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                children: [
                  Text(error!, key: const ValueKey('map-network-error')),
                  TextButton.icon(
                    onPressed: checking ? null : _retry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Riprova'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                if (available || mapReady)
                  FlutterMap(
                    key: const ValueKey('location-map'),
                    mapController: controller,
                    options: MapOptions(
                      interactionOptions: northUpInteractions,
                      initialCenter: searchCenter ?? initial,
                      initialZoom: searchCenter == null ? zoom : 13,
                      minZoom: 2,
                      maxZoom: 19,
                      onMapReady: () => setState(() => mapReady = true),
                      onTap: (_, point) {
                        FocusScope.of(context).unfocus();
                        if (!available || checking || uncertaintyError != null) {
                          return;
                        }
                        setState(
                          () => selected = LatLng(
                            point.latitude.clamp(-85.05112878, 85.05112878),
                            (point.longitude + 180) % 360 - 180,
                          ),
                        );
                      },
                    ),
                    children: [
                      TileLayer(
                        key: ValueKey('map-tiles-$generation'),
                        urlTemplate: layer.template,
                        userAgentPackageName: 'it.italic.italicapp',
                        tileProvider: tileProvider,
                        panBuffer: 0,
                        maxNativeZoom: 19,
                        errorTileCallback: (_, _, _) => _tileFailed(),
                      ),
                      if (selected != null &&
                          uncertaintyError == null &&
                          uncertaintyValue != null)
                        CircleLayer(
                          circles: [
                            CircleMarker(
                              point: selected!,
                              radius: uncertaintyValue!,
                              useRadiusInMeter: true,
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: .12),
                              borderColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              borderStrokeWidth: 1.5,
                            ),
                          ],
                        ),
                      MarkerLayer(
                        markers: [
                          if (selected != null || hasInitial)
                            Marker(
                              point: selected ?? initial,
                              width: 48,
                              height: 48,
                              alignment: Alignment.topCenter,
                              child: Icon(
                                Icons.location_pin,
                                size: 48,
                                color: selected == null
                                    ? Colors.blueGrey
                                    : Theme.of(context).colorScheme.primary,
                              ),
                            ),
                        ],
                      ),
                    ],
                  )
                else
                  const Center(
                    child: Icon(
                      Icons.map_outlined,
                      size: 72,
                      color: Colors.grey,
                    ),
                  ),
                if (mapReady)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Card(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Ingrandisci',
                            icon: const Icon(Icons.add),
                            onPressed: () => controller.move(
                              controller.camera.center,
                              (controller.camera.zoom + 1).clamp(2, 19),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Riduci',
                            icon: const Icon(Icons.remove),
                            onPressed: () => controller.move(
                              controller.camera.center,
                              (controller.camera.zoom - 1).clamp(2, 19),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (available || mapReady)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: MapCredits(layer: layer),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  selected == null
                      ? 'Tocca la mappa per scegliere un punto.'
                      : '${selected!.latitude.toStringAsFixed(6)}, ${selected!.longitude.toStringAsFixed(6)}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                const Text(
                  'L’incertezza è una tua stima; la mappa non misura la quota o la precisione GPS.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  key: const ValueKey('confirm-map-location'),
                  onPressed:
                      selected == null ||
                          !available ||
                          checking ||
                          uncertaintyError != null
                      ? null
                      : () => _check(confirm: true),
                  icon: const Icon(Icons.check),
                  label: const Text('Usa questo punto'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
