import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/diary_filter.dart';
import '../services/online_map.dart';
import '../widgets/map_tools.dart';

class AreaFilterPage extends StatefulWidget {
  const AreaFilterPage({super.key, this.initial});
  final GeoRectangle? initial;
  @override
  State<AreaFilterPage> createState() => _AreaFilterPageState();
}

class _AreaFilterPageState extends State<AreaFilterPage> {
  final controller = MapController();
  MapBaseLayer layer = MapBaseLayer.street;
  LatLng? first, second;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  bool checking = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    if (r != null) {
      first = LatLng(r.south, r.west);
      second = LatLng(r.north, r.east);
    }
  }

  GeoRectangle? get rectangle => first == null || second == null
      ? null
      : GeoRectangle(
          math.min(first!.latitude, second!.latitude),
          math.min(first!.longitude, second!.longitude),
          math.max(first!.latitude, second!.latitude),
          math.max(first!.longitude, second!.longitude),
        );
  Future<void> confirm() async {
    final r = rectangle;
    if (r == null || r.north == r.south || r.west == r.east) return;
    setState(() {
      checking = true;
      error = null;
    });
    final online = OnlineMap();
    try {
      await online.checkSource(
        (r.north + r.south) / 2,
        (r.west + r.east) / 2,
        5,
        template: layer.template,
      );
      if (mounted) Navigator.pop(context, r);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Serve una connessione per scegliere l’area sulla mappa. Riprova.',
        );
      }
    } finally {
      online.close();
      if (mounted) setState(() => checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = rectangle;
    return Scaffold(
      appBar: AppBar(title: const Text('Seleziona un’area')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Tocca due angoli opposti del rettangolo. Un terzo tocco ricomincia la selezione. La mappa richiede internet; il filtro funziona poi anche offline.',
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: MapTools(
              layer: layer,
              enabled: !checking,
              onLayer: (v) => setState(() => layer = v),
              onPlace: (p) => focusPlace(controller, p),
            ),
          ),
          Expanded(
            child: FlutterMap(
              mapController: controller,
              options: MapOptions(
                interactionOptions: northUpInteractions,
                initialCenter: first ?? const LatLng(42, 12),
                initialZoom: 5,
                onTap: checking
                    ? null
                    : (_, p) => setState(() {
                        error = null;
                        if (first == null || second != null) {
                          first = p;
                          second = null;
                        } else {
                          second = p;
                        }
                      }),
              ),
              children: [
                TileLayer(
                  urlTemplate: layer.template,
                  userAgentPackageName: 'it.italic.italicapp',
                  panBuffer: 0,
                ),
                if (r != null)
                  PolygonLayer(
                    polygons: [
                      Polygon(
                        points: [
                          LatLng(r.south, r.west),
                          LatLng(r.north, r.west),
                          LatLng(r.north, r.east),
                          LatLng(r.south, r.east),
                        ],
                        color: Colors.green.withValues(alpha: .2),
                        borderColor: Colors.green,
                        borderStrokeWidth: 3,
                      ),
                    ],
                  ),
                if (first != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: first!,
                        child: const Icon(
                          Icons.add_location,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                Align(
                  alignment: Alignment.bottomRight,
                  child: MapCredits(layer: layer),
                ),
              ],
            ),
          ),
          if (error != null)
            Padding(padding: const EdgeInsets.all(12), child: Text(error!)),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: checking
                        ? null
                        : () => setState(() {
                            first = null;
                            second = null;
                          }),
                    child: const Text('Ricomincia'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed:
                          checking ||
                              r == null ||
                              r.south == r.north ||
                              r.west == r.east
                          ? null
                          : confirm,
                      child: Text(checking ? 'Verifica…' : 'Usa quest’area'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
