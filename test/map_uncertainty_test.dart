import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:italicapp/models/field_plot.dart';
import 'package:italicapp/models/observation.dart';
import 'package:italicapp/services/field_dataset.dart';
import 'package:italicapp/services/field_location.dart';
import 'package:italicapp/services/observation_export.dart';
import 'plots_test.dart' as fixtures;

void main() {
  test(
    'Manual uncertainty is independent of GPS accuracy and disappears on a fresh GPS fix',
    () {
      final original = Observation(
        id: 'o',
        createdAt: DateTime.now(),
        latitude: 45,
        longitude: 11,
        horizontalAccuracy: 3,
        seaLevelAltitude: 400,
        notes: 'Da conservare',
      );
      final manual = original.withMapPosition(
        46,
        12,
        uncertaintyInMeters: 25.5,
      );
      expect(manual.positionUncertaintyInMeters, 25.5);
      expect(manual.horizontalAccuracy, isNull);
      expect(manual.seaLevelAltitude, isNull);
      expect(manual.notes, original.notes);
      expect(original.horizontalAccuracy, 3);
      expect(
        Observation.fromMap(manual.toMap()).coordinateUncertaintyInMeters,
        25.5,
      );
      for (final value in [
        0.0,
        -1.0,
        double.nan,
        double.infinity,
        20000001.0,
      ]) {
        expect(
          () => original.withMapPosition(46, 12, uncertaintyInMeters: value),
          throwsArgumentError,
        );
      }
      expect(
        manual.withMapPosition(47, 13).coordinateUncertaintyInMeters,
        isNull,
      );
      final gps = FieldFix(
        latitude: 45,
        longitude: 11,
        accuracy: 4,
        timestamp: DateTime.now(),
        seaLevelAltitude: 500,
      ).applyTo(manual);
      expect(gps.coordinateUncertaintyInMeters, isNull);
      expect(gps.positionUncertaintyInMeters, 4);
      expect(gps.seaLevelAltitude, 500);
    },
  );

  test(
    'Darwin Core, GeoJSON and summaries keep manual uncertainty and respect the coordinate opt-out',
    () {
      final manual = Observation(
        id: 'o',
        createdAt: DateTime.now(),
      ).withMapPosition(46, 12, uncertaintyInMeters: 25.5);
      final dataset = FieldDataset(observations: [manual], plots: []);
      final record = dataset.records(includeGps: true).single;
      expect(record['coordinateUncertaintyInMeters'], 25.5);
      expect(
        jsonDecode(
          record['dynamicProperties'] as String,
        )['coordinateUncertaintySource'],
        'user_estimate',
      );
      expect(dataset.records().single['coordinateUncertaintyInMeters'], isNull);
      expect(
        observationSummary([manual], includeGps: true),
        contains('Incertezza stimata manualmente: 25.5'),
      );
      expect(
        observationSummary([manual], includeGps: true),
        isNot(contains('Accuratezza GPS')),
      );
      for (final format in [
        ObservationExportFormat.geojson,
        ObservationExportFormat.csv,
        ObservationExportFormat.darwinCore,
      ]) {
        final exported = utf8.decode(
          exportObservations(
            [manual],
            format,
            includeGps: true,
          ).files.single.bytes,
        );
        expect(exported, contains('25.5'));
        expect(
          utf8.decode(exportObservations([manual], format).files.single.bytes),
          isNot(contains('25.5')),
        );
      }
    },
  );

  test(
    'Plot uncertainty survives reopening, photo inheritance and keeping photos after plot deletion',
    () async {
      final store = await fixtures.plotStore();
      final plot = FieldPlot.fromMap({
        ...fixtures.example().toMap(),
        'horizontalAccuracy': null,
        'coordinateUncertaintyInMeters': 50.0,
        'positionSource': 'manual_map',
        'seaLevelAltitude': null,
      });
      await store.savePlot(plot);
      await store.save(
        Observation(id: 'photo', createdAt: DateTime.now(), plotId: plot.id),
      );
      final dataset = FieldDataset.fromStore(store);
      expect(
        dataset
            .records(includeGps: true)
            .single['coordinateUncertaintyInMeters'],
        50,
      );
      expect(store.mapObservations.single.coordinateUncertaintyInMeters, 50);
      expect(
        (await store.plotRepository.all()).single.coordinateUncertaintyInMeters,
        50,
      );
      final workbook = dataset.workbook(includeGps: true);
      final plotRows = workbook['Plots']!;
      expect(
        plotRows[1][plotRows.first.indexOf('coordinateUncertaintyInMeters')],
        50,
      );
      await store.deletePlot(plot, deletePhotos: false);
      final saved = (await store.repository.all()).single;
      expect(saved.coordinateUncertaintyInMeters, 50);
      expect(saved.horizontalAccuracy, isNull);
      expect(saved.positionUncertaintyInMeters, 50);
      expect(
        FieldDataset.fromStore(
          store,
        ).records(includeGps: true).single['coordinateUncertaintyInMeters'],
        50,
      );
      await store.repository.close();
      await store.plotRepository.close();
    },
  );
}
