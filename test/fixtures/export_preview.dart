// Visual verification only: no device location, camera or persistent database.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:italicapp/app_store.dart';
import 'package:italicapp/data/observation_repository.dart';
import 'package:italicapp/main.dart';
import 'package:italicapp/models/observation.dart';
import 'package:italicapp/models/identification_path.dart';
import 'package:italicapp/theme/app_theme.dart';

void main() {
  final store = AppStore(ObservationRepository(factory: newIdbFactoryMemory()))
    ..loading = false
    ..observations = [
      Observation(
        id: 'campione-simulato',
        createdAt: DateTime.utc(2026, 11, 2, 12),
        latitude: 0,
        longitude: 0,
        horizontalAccuracy: 3,
        rank: IdentificationRank.species,
        taxonName: 'Physcia adscendens · campione simulato',
        substrate: 'Corteccia',
        notes: 'Dati di prova: nessuna osservazione reale.',
        photoName: 'prova.png',
        photoBytes: base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=',
        ),
        identificationPath: IdentificationPath(
          keyId: 'physcia',
          answers: {'cilia': KeyAnswer.a},
          savedAt: DateTime.utc(2026, 11, 2),
        ),
      ),
    ];
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Scaffold(
        body: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                'Anteprima di prova · dati simulati, archivio solo in memoria',
              ),
            ),
            Expanded(child: Shell(store: store)),
          ],
        ),
      ),
    ),
  );
}
