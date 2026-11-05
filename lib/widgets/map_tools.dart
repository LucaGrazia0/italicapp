import 'package:latlong2/latlong.dart';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:url_launcher/link.dart';
import '../services/online_map.dart';
import '../services/place_search.dart';

const northUpInteractions = InteractionOptions(
  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
);
void focusPlace(MapController controller, PlaceResult place) {
  if (place.south != null &&
      place.south != place.north &&
      place.west != place.east) {
    controller.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints([
          LatLng(place.south!, place.west!),
          LatLng(place.north!, place.east!),
        ]),
        padding: const EdgeInsets.all(36),
        maxZoom: 16,
      ),
    );
  } else {
    controller.move(place.point, 13);
  }
}

class MapTools extends StatelessWidget {
  const MapTools({
    super.key,
    required this.layer,
    required this.onLayer,
    required this.onPlace,
    this.enabled = true,
  });
  final MapBaseLayer layer;
  final ValueChanged<MapBaseLayer> onLayer;
  final ValueChanged<PlaceResult> onPlace;
  final bool enabled;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: SegmentedButton<MapBaseLayer>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: MapBaseLayer.street,
              icon: Icon(Icons.map_outlined, size: 18),
              label: Text('Mappa'),
            ),
            ButtonSegment(
              value: MapBaseLayer.satellite,
              icon: Icon(Icons.satellite_alt, size: 18),
              label: Text('Satellite'),
            ),
          ],
          selected: {layer},
          onSelectionChanged: enabled ? (v) => onLayer(v.single) : null,
        ),
      ),
      const SizedBox(width: 8),
      IconButton.filledTonal(
        key: const ValueKey('search-map-place'),
        tooltip: 'Cerca per località',
        onPressed: enabled
            ? () async {
                final result = await Navigator.push<PlaceResult>(
                  context,
                  MaterialPageRoute(builder: (_) => const PlaceSearchPage()),
                );
                if (result != null && context.mounted) onPlace(result);
              }
            : null,
        icon: const Icon(Icons.travel_explore),
      ),
    ],
  );
}

class MapCredits extends StatelessWidget {
  const MapCredits({super.key, required this.layer});
  final MapBaseLayer layer;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.white.withValues(alpha: .9),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Link(
        uri: Uri.parse(layer.creditUrl),
        target: LinkTarget.blank,
        builder: (_, follow) => InkWell(
          onTap: follow,
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Text(
              layer.credits,
              style: const TextStyle(color: Colors.black87, fontSize: 10),
            ),
          ),
        ),
      ),
    ),
  );
}

class PlaceSearchPage extends StatefulWidget {
  const PlaceSearchPage({super.key, this.lookup});
  final Future<List<PlaceResult>> Function(String)? lookup;
  @override
  State<PlaceSearchPage> createState() => _PlaceSearchPageState();
}

class _PlaceSearchPageState extends State<PlaceSearchPage> {
  final query = TextEditingController(), service = PlaceSearch();
  List<PlaceResult>? results;
  String? error;
  bool busy = false;
  int request = 0;
  @override
  void dispose() {
    request++;
    query.dispose();
    service.close();
    super.dispose();
  }

  Future<void> search() async {
    if (busy) return;
    final text = query.text.trim();
    if (text.length < 3) {
      setState(() => error = 'Scrivi almeno tre caratteri.');
      return;
    }
    final ticket = ++request;
    setState(() {
      busy = true;
      error = null;
      results = null;
    });
    try {
      final value = await (widget.lookup ?? service.search)(text);
      if (mounted && ticket == request) setState(() => results = value);
    } catch (_) {
      if (mounted && ticket == request) {
        setState(
          () => error =
              'Ricerca non disponibile. Controlla la connessione e riprova.',
        );
      }
    } finally {
      if (mounted && ticket == request) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Cerca per località')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Cerca una città, un paese, un monte o una località. La ricerca usa internet e sposta soltanto la vista: non modifica i ritrovamenti né sceglie automaticamente una posizione.',
        ),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('place-query'),
          controller: query,
          enabled: !busy,
          decoration: const InputDecoration(
            labelText: 'Località',
            hintText: 'Es. Paneveggio, Trentino',
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => search(),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const ValueKey('submit-place-search'),
          onPressed: busy ? null : search,
          icon: const Icon(Icons.search),
          label: Text(busy ? 'Ricerca…' : 'Cerca'),
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text(error!),
        if (results?.isEmpty == true)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Nessuna località trovata. Prova un nome diverso o aggiungi la regione.',
            ),
          ),
        for (final place in results ?? <PlaceResult>[])
          ListTile(
            title: Text(place.label),
            leading: const Icon(Icons.location_city),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pop(context, place),
          ),
        const SizedBox(height: 20),
        Link(
          uri: Uri.parse('https://photon.komoot.io/'),
          target: LinkTarget.blank,
          builder: (_, follow) => TextButton(
            onPressed: follow,
            child: const Text(
              'Ricerca Photon / komoot · dati © OpenStreetMap contributors',
            ),
          ),
        ),
      ],
    ),
  );
}
