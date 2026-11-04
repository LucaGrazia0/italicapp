import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/link.dart';
import '../app_store.dart';
import '../models/observation.dart';
import '../services/online_map.dart';
import '../theme/app_theme.dart';
import 'observation_page.dart';
import 'plot_page.dart';

class FindingsMapPage extends StatefulWidget {
  const FindingsMapPage({
    super.key,
    required this.store,
    this.tileProvider,
    this.onOpen,
  });
  final AppStore store;
  final TileProvider? tileProvider;
  final ValueChanged<Observation>? onOpen;
  @override
  State<FindingsMapPage> createState() => _FindingsMapPageState();
}

class _FindingsMapPageState extends State<FindingsMapPage> {
  final controller = MapController();
  bool ready = false, failed = false;
  int generation = 0;
  String query = '';
  List<Observation> get records => widget.store.mapObservations
      .where(
        (o) =>
            query.isEmpty ||
            (o.taxonName ?? 'Non determinato').toLowerCase().contains(query) ||
            (widget.store
                    .plotById(o.plotId ?? '')
                    ?.name
                    .toLowerCase()
                    .contains(query) ??
                false),
      )
      .toList();
  LatLng point(Observation o) =>
      LatLng(o.latitude!.clamp(-85.05112878, 85.05112878), o.longitude!);
  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.store.addListener(changed);
  }

  @override
  void dispose() {
    widget.store.removeListener(changed);
    controller.dispose();
    super.dispose();
  }

  void open(Observation o) {
    Observation? original;
    for (final observation in widget.store.observations) {
      if (observation.id == o.id) {
        original = observation;
        break;
      }
    }
    if (widget.onOpen != null) {
      widget.onOpen!(original ?? o);
      return;
    }
    if (original == null && o.plotId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlotPage(store: widget.store, plotId: o.plotId!),
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        settings: RouteSettings(
          name: ObservationPage.routeName(original?.id ?? o.id),
        ),
        builder: (_) =>
            ObservationPage(observation: original ?? o, store: widget.store),
      ),
    );
  }

  void showRecords(
    List<Observation> observations,
  ) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .65,
        child: ListView.builder(
          itemCount: observations.length,
          itemBuilder: (_, i) {
            final o = observations[i];
            return ListTile(
              key: ValueKey('map-record-${o.id}'),
              leading: Icon(
                o.hasPosition
                    ? Icons.location_on_outlined
                    : Icons.location_off_outlined,
                color: AppTheme.forest,
              ),
              title: Text(o.taxonName ?? 'Non determinato'),
              subtitle: Text(
                o.hasPosition
                    ? '${o.latitude!.toStringAsFixed(5)}, ${o.longitude!.toStringAsFixed(5)} · ${o.createdAt.day}/${o.createdAt.month}/${o.createdAt.year}'
                    : 'Posizione da aggiungere dal diario',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(sheet);
                open(o);
              },
            );
          },
        ),
      ),
    ),
  );
  void fit(List<Observation> observations) {
    if (!ready || observations.isEmpty) return;
    if (observations.length == 1) {
      controller.move(point(observations.first), 15);
      return;
    }
    controller.fitCamera(
      CameraFit.coordinates(
        coordinates: observations.map(point).toList(),
        padding: const EdgeInsets.all(48),
        maxZoom: 16,
      ),
    );
  }

  void tileFailed() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && !failed) setState(() => failed = true);
  });

  @override
  Widget build(BuildContext context) {
    final all = records;
    final located = all.where((o) => o.hasPosition).toList();
    final missing = all.length - located.length;
    final groups = <String, List<Observation>>{};
    for (final o in located) {
      groups
          .putIfAbsent(
            '${o.latitude!.toStringAsFixed(6)},${o.longitude!.toStringAsFixed(6)}',
            () => [],
          )
          .add(o);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'I tuoi ritrovamenti',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppTheme.forest,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${located.length} ritrovamenti sulla mappa${missing > 0 ? ' · $missing senza posizione' : ''}',
                key: const ValueKey('findings-count'),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('findings-search'),
                decoration: const InputDecoration(
                  hintText: 'Cerca tra le specie trovate',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
                onChanged: (value) =>
                    setState(() => query = value.trim().toLowerCase()),
              ),
            ],
          ),
        ),
        if (all.isEmpty)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  query.isEmpty
                      ? 'Nessun ritrovamento nel diario. Aggiungi una foto e la posizione per vederlo qui.'
                      : 'Nessun ritrovamento corrisponde alla ricerca.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          )
        else ...[
          if (failed)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Mappa online non disponibile. I ritrovamenti restano consultabili nella lista.',
                      key: ValueKey('findings-map-offline'),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      generation++;
                      failed = false;
                    }),
                    child: const Text('Riprova'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                if (located.isNotEmpty)
                  FlutterMap(
                    mapController: controller,
                    options: MapOptions(
                      initialCenter: point(located.first),
                      initialZoom: located.length == 1 ? 15 : 5,
                      initialCameraFit: located.length > 1
                          ? CameraFit.coordinates(
                              coordinates: located.map(point).toList(),
                              padding: const EdgeInsets.all(48),
                              maxZoom: 16,
                            )
                          : null,
                      onMapReady: () => ready = true,
                      minZoom: 2,
                      maxZoom: 19,
                    ),
                    children: [
                      TileLayer(
                        key: ValueKey('findings-tiles-$generation'),
                        urlTemplate: OnlineMap.tileTemplate,
                        userAgentPackageName: 'it.italic.italicapp',
                        tileProvider: widget.tileProvider,
                        panBuffer: 0,
                        maxNativeZoom: 19,
                        errorTileCallback: (_, _, _) => tileFailed(),
                      ),
                      MarkerLayer(
                        markers: [
                          for (final group in groups.values)
                            Marker(
                              point: point(group.first),
                              width: 52,
                              height: 52,
                              alignment: Alignment.topCenter,
                              child: Semantics(
                                button: true,
                                label:
                                    '${group.length} ritrovamenti: ${group.map((o) => o.taxonName ?? 'Non determinato').join(', ')}',
                                child: InkWell(
                                  key: ValueKey(
                                    'findings-marker-${group.first.id}',
                                  ),
                                  onTap: () => showRecords(group),
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      const Icon(
                                        Icons.location_pin,
                                        size: 50,
                                        color: AppTheme.forest,
                                      ),
                                      Positioned(
                                        top: 8,
                                        child: Text(
                                          '${group.length}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  )
                else
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Aggiungi una posizione ai ritrovamenti dal diario per visualizzarli sulla mappa.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                if (located.isNotEmpty)
                  Positioned(
                    right: 12,
                    top: 12,
                    child: FloatingActionButton.small(
                      heroTag: 'findings-fit',
                      tooltip: 'Mostra tutti i ritrovamenti',
                      onPressed: () => fit(located),
                      child: const Icon(Icons.center_focus_strong),
                    ),
                  ),
                if (located.isNotEmpty)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: ColoredBox(
                      color: Colors.white,
                      child: Link(
                        uri: Uri.parse(
                          'https://www.openstreetmap.org/copyright',
                        ),
                        target: LinkTarget.blank,
                        builder: (_, follow) => TextButton(
                          onPressed: follow,
                          child: const Text(
                            '© OpenStreetMap contributors',
                            style: TextStyle(fontSize: 10),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              key: const ValueKey('findings-list'),
              onPressed: () => showRecords(all),
              icon: const Icon(Icons.list_alt),
              label: Text('Vedi i ritrovamenti (${all.length})'),
            ),
          ),
        ],
      ],
    );
  }
}
