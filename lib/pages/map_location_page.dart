import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../widgets/map_tools.dart';
import '../models/map_position.dart';
import '../services/map_uncertainty.dart';
import '../services/online_map.dart';

enum MapUncertaintyMode { circle, meters, unknown }

class MapLocationPage extends StatefulWidget {
  const MapLocationPage({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    this.initialUncertaintyInMeters,
    this.onlineMap,
    this.tileProvider,
  });
  final double? initialLatitude, initialLongitude, initialUncertaintyInMeters;
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
  late MapUncertaintyMode mode = uncertainty.text.isNotEmpty
      ? MapUncertaintyMode.meters
      : MapUncertaintyMode.circle;
  late final onlineMap = widget.onlineMap ?? OnlineMap();
  late TileProvider tileProvider;
  late final hasInitial =
      widget.initialLatitude != null &&
      widget.initialLongitude != null &&
      widget.initialLatitude!.isFinite &&
      widget.initialLongitude!.isFinite;
  late final initial = hasInitial
      ? MapUncertainty.normalize(
          LatLng(widget.initialLatitude!, widget.initialLongitude!),
        )
      : const LatLng(42.5, 12.5);
  late final zoom = hasInitial ? 15.0 : 5.0;
  LatLng? selected, searchCenter;
  MapCamera? camera;
  MapBaseLayer layer = MapBaseLayer.street;
  bool checking = true,
      available = false,
      mapReady = false,
      updateQueued = false;
  int generation = 0;
  String? error;

  double? get manualValue =>
      double.tryParse(uncertainty.text.trim().replaceAll(',', '.'));
  String? get uncertaintyError {
    if (mode != MapUncertaintyMode.meters || uncertainty.text.trim().isEmpty) {
      return null;
    }
    return manualValue != null && MapPosition.validUncertainty(manualValue)
        ? null
        : 'Inserisci un numero maggiore di 0, fino a 20.000.000 m.';
  }

  double? get radius => switch (mode) {
    MapUncertaintyMode.circle =>
      camera == null ? null : MapUncertainty.radiusInMeters(camera!),
    MapUncertaintyMode.meters => uncertaintyError == null ? manualValue : null,
    MapUncertaintyMode.unknown => null,
  };
  Color get areaColor => radius != null && radius! > 100
      ? const Color(0xFFE3AC32)
      : Theme.of(context).colorScheme.primary;

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

  // Camera callbacks may run during layout: refresh the UI after that frame.
  void _cameraChanged(MapCamera value, {bool choose = false}) {
    camera = value;
    if (choose && available && !checking) {
      selected = MapUncertainty.normalize(value.center);
    }
    if (updateQueued) return;
    updateQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      updateQueued = false;
      if (mounted) setState(() {});
    });
  }

  void _move(LatLng point, double newZoom) {
    if (!mapReady || !available || checking) return;
    FocusScope.of(context).unfocus();
    controller.move(MapUncertainty.normalize(point), newZoom.clamp(2, 19));
    _cameraChanged(controller.camera, choose: true);
  }

  void _mode(MapUncertaintyMode value) {
    setState(() {
      mode = value;
      if (mapReady && available && hasInitial) {
        selected = MapUncertainty.normalize(controller.camera.center);
      }
    });
  }

  Future<void> _check({bool confirm = false}) async {
    if (confirm && (selected == null || uncertaintyError != null)) return;
    // Save exactly the point and radius visible when the button is pressed.
    final result = confirm
        ? MapPosition(
            selected!.latitude,
            selected!.longitude,
            uncertaintyInMeters: radius,
          )
        : null;
    final point = result == null
        ? (mapReady ? controller.camera.center : searchCenter ?? initial)
        : LatLng(result.latitude, result.longitude);
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
      if (result != null && error == null) {
        Navigator.pop(context, result);
        return;
      }
      setState(() {
        available = error == null;
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || error != null) return;
      setState(() {
        available = false;
        error =
            'Alcune parti della mappa non si caricano. Controlla la connessione e riprova prima di salvare il punto.';
      });
    });
  }

  void _retry() {
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
  Widget build(BuildContext context) {
    final currentPoint = camera == null
        ? initial
        : MapUncertainty.normalize(camera!.center);
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: const Text('Scegli il punto sulla mappa')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
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
                  // Search moves the view; the user still explicitly chooses the point.
                  setState(() => searchCenter = p.point);
                  if (mapReady) focusPlace(controller, p);
                  _check();
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<MapUncertaintyMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: MapUncertaintyMode.circle,
                      label: Text('Dal cerchio'),
                    ),
                    ButtonSegment(
                      value: MapUncertaintyMode.meters,
                      label: Text('In metri'),
                    ),
                    ButtonSegment(
                      value: MapUncertaintyMode.unknown,
                      label: Text('Non nota'),
                    ),
                  ],
                  selected: {mode},
                  onSelectionChanged: checking ? null : (v) => _mode(v.single),
                ),
              ),
            ),
            if (mode == MapUncertaintyMode.meters)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
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
                  onChanged: (_) {
                    setState(() {
                      if (mapReady &&
                          available &&
                          (selected != null || hasInitial)) {
                        selected = MapUncertainty.normalize(
                          controller.camera.center,
                        );
                      }
                    });
                  },
                  onSubmitted: (_) => FocusScope.of(context).unfocus(),
                ),
              ),
            if (checking) const LinearProgressIndicator(),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
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
                fit: StackFit.expand,
                children: [
                  if (available || mapReady)
                    FlutterMap(
                      key: const ValueKey('location-map'),
                      mapController: controller,
                      options: MapOptions(
                        interactionOptions: checking || !available
                            ? const InteractionOptions(
                                flags: InteractiveFlag.none,
                              )
                            : northUpInteractions,
                        initialCenter: searchCenter ?? initial,
                        initialZoom: searchCenter == null ? zoom : 13,
                        minZoom: 2,
                        maxZoom: 19,
                        onMapReady: () {
                          mapReady = true;
                          _cameraChanged(controller.camera);
                        },
                        onPositionChanged: (value, gesture) {
                          if (mapReady) {
                            _cameraChanged(
                              value,
                              choose: gesture || selected != null,
                            );
                          }
                        },
                        onTap: (_, point) =>
                            _move(point, controller.camera.zoom),
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
                        if (mode == MapUncertaintyMode.meters &&
                            radius != null &&
                            camera != null)
                          CircleLayer(
                            circles: [
                              CircleMarker(
                                point: currentPoint,
                                radius: radius!,
                                useRadiusInMeter: true,
                                color: areaColor.withValues(alpha: .12),
                                borderColor: areaColor,
                                borderStrokeWidth: 2.5,
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
                    IgnorePointer(
                      child: CustomPaint(
                        key: const ValueKey('map-uncertainty-target'),
                        painter: _MapTargetPainter(
                          color: areaColor,
                          circle: mode == MapUncertaintyMode.circle,
                        ),
                      ),
                    ),
                  if (camera != null)
                    Positioned(
                      top: 10,
                      left: 12,
                      right: 70,
                      child: Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${currentPoint.latitude.toStringAsFixed(6)}, ${currentPoint.longitude.toStringAsFixed(6)}',
                                key: const ValueKey('map-point-coordinates'),
                                style: const TextStyle(fontSize: 12),
                              ),
                              Text(
                                'Raggio: ${MapUncertainty.label(radius)}',
                                key: const ValueKey('map-uncertainty-radius'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (mapReady)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Card(
                        margin: EdgeInsets.zero,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Ingrandisci',
                              icon: const Icon(Icons.add),
                              onPressed: checking || !available
                                  ? null
                                  : () => _move(
                                      controller.camera.center,
                                      controller.camera.zoom + 1,
                                    ),
                            ),
                            IconButton(
                              tooltip: 'Riduci',
                              icon: const Icon(Icons.remove),
                              onPressed: checking || !available
                                  ? null
                                  : () => _move(
                                      controller.camera.center,
                                      controller.camera.zoom - 1,
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
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    selected == null
                        ? 'Sposta o tocca la mappa per scegliere il punto.'
                        : 'Il punto da salvare è al centro del mirino.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    mode == MapUncertaintyMode.circle
                        ? 'Ingrandisci per restringere l’area. Il raggio è stimato dallo zoom, non misurato dal GPS.'
                        : mode == MapUncertaintyMode.meters
                        ? 'Il raggio in metri resta fisso quando ingrandisci. La mappa non misura la quota o la precisione GPS.'
                        : 'Incertezza non indicata. La mappa non misura la quota o la precisione GPS.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    key: const ValueKey('confirm-map-location'),
                    onPressed:
                        selected == null ||
                            !available ||
                            checking ||
                            uncertaintyError != null ||
                            (mode == MapUncertaintyMode.circle &&
                                radius == null)
                        ? null
                        : () => _check(confirm: true),
                    icon: const Icon(Icons.check),
                    label: const Text('Salva posizione'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapTargetPainter extends CustomPainter {
  const _MapTargetPainter({required this.color, required this.circle});
  final Color color;
  final bool circle;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = MapUncertainty.screenRadius(size);
    if (radius <= 0) return;
    final extent = circle ? radius : math.min(radius, 28.0);
    final crosshair = Paint()
      ..color = const Color(0xFF253C32).withValues(alpha: .75)
      ..strokeWidth = 1.5;
    canvas.drawLine(
      center.translate(-extent, 0),
      center.translate(extent, 0),
      crosshair,
    );
    canvas.drawLine(
      center.translate(0, -extent),
      center.translate(0, extent),
      crosshair,
    );
    if (circle) {
      final bounds = Rect.fromCircle(center: center, radius: radius);
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = color.withValues(alpha: .08),
      );
      final stroke = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4;
      for (double angle = 0; angle < math.pi * 2; angle += .23) {
        canvas.drawArc(bounds, angle, .14, false, stroke);
      }
    }
    canvas.drawCircle(center, 5, Paint()..color = Colors.white);
    canvas.drawCircle(center, 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_MapTargetPainter oldDelegate) =>
      color != oldDelegate.color || circle != oldDelegate.circle;
}
