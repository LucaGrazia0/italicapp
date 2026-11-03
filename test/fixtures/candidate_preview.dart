// Isolated visual verification: simulated observation, memory-only store.
import 'package:flutter/material.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:italicapp/app_store.dart';
import 'package:italicapp/data/observation_repository.dart';
import 'package:italicapp/models/observation.dart';
import 'package:italicapp/models/identification_path.dart';
import 'package:italicapp/services/reconstructed_key.dart';
import 'package:italicapp/pages/reconstructed_key_page.dart';
import 'package:italicapp/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final definition = await ReconstructedKey.load();
  final observation = Observation(
    id: 'isolated-candidate-preview',
    createdAt: DateTime.utc(2026, 11, 2),
    latitude: 0,
    longitude: 0,
    horizontalAccuracy: 0,
    notes: 'Dati simulati: nessuna osservazione reale modificata.',
    identificationPath: IdentificationPath(
      keyId: definition.identity,
      answers: const {},
      selections: const {
        'lead_1504': 'lead_1676',
        'lead_1676': 'lead_1820',
        'lead_1820': 'lead_1846',
      },
      savedAt: DateTime.utc(2026, 11, 2),
    ),
  );
  final store = _PreviewStore();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              AnimatedBuilder(
                animation: store,
                builder: (context, _) => Container(
                  width: double.infinity,
                  color: const Color(0xFFEAF0E9),
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Diario di prova · ${store.observations.isEmpty ? "Non determinato" : store.observations.single.taxonName}\nDati simulati, archivio solo in memoria.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              Expanded(
                child: ReconstructedKeyPage(
                  definition: definition,
                  observation: observation,
                  store: store,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _PreviewStore extends AppStore {
  _PreviewStore()
    : super(ObservationRepository(factory: newIdbFactoryMemory()));
  @override
  Future<void> save(Observation observation) async {
    observations = [Observation.fromMap(observation.toMap())];
    notifyListeners();
  }
}
