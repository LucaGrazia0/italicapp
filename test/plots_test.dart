import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:image_picker/image_picker.dart';
import 'package:italicapp/app_store.dart';
import 'package:italicapp/data/observation_repository.dart';
import 'package:italicapp/data/plot_repository.dart';
import 'package:italicapp/data/italic_reference_repository.dart';
import 'package:italicapp/models/field_plot.dart';
import 'package:italicapp/models/observation.dart';
import 'package:italicapp/services/field_achievements.dart';
import 'package:italicapp/services/plot_photos.dart';

final stamp = DateTime(2026, 11, 4);
FieldPlot example({List<PlotSpecies> species = const []}) => FieldPlot(
  id: 'p',
  name: 'Bosco · plot 01',
  sampledAt: stamp,
  createdAt: stamp,
  notes: 'Corteccia',
  areaM2: 25,
  latitude: 45,
  longitude: 11,
  seaLevelAltitude: 321,
  positionSource: 'gps',
  species: species,
);
const plotTaxa = [
  ItalicTaxon(scientificName: 'Physcia aipolia', italicId: 1717),
  ItalicTaxon(scientificName: 'Peltigera canina', italicId: 222),
];
final bytes = File(
  'android/app/src/main/res/mipmap-mdpi/ic_launcher.png',
).readAsBytesSync();
XFile photo(int n) => XFile.fromData(
  Uint8List.fromList([...bytes, n]),
  name: 'photo-$n.png',
  mimeType: 'image/png',
);

class PlotPicker extends ImagePicker {
  List<XFile> files = [];
  LostDataResponse? lost;
  bool? metadata;
  ImageSource? source;
  @override
  Future<List<XFile>> pickMultiImage({
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    int? limit,
    bool requestFullMetadata = true,
  }) async {
    metadata = requestFullMetadata;
    return files;
  }

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    this.source = source;
    metadata = requestFullMetadata;
    return files.isEmpty ? null : files.first;
  }

  @override
  Future<LostDataResponse> retrieveLostData() async =>
      lost ?? LostDataResponse.empty();
}

class FailingPlots extends PlotRepository {
  FailingPlots() : super(factory: newIdbFactoryMemory());
  bool fail = false;
  @override
  Future<void> save(FieldPlot p) async {
    if (fail) throw StateError('Disk unavailable');
    await super.save(p);
  }
}

Future<AppStore> plotStore() async {
  final s = AppStore(ObservationRepository(factory: newIdbFactoryMemory()));
  await s.init();
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Plots, annotations and linked image bytes survive reopening; legacy observations are unchanged',
    () async {
      final s = await plotStore();
      final old = Observation(
        id: 'old',
        createdAt: stamp,
        notes: 'existing diary',
      );
      await s.save(old);
      final plot = example(
        species: [
          const PlotSpecies(
            name: 'Physcia aipolia',
            italicId: 1717,
            abundance: '15%',
            notes: 'north',
          ),
        ],
      );
      await s.savePlot(plot);
      await PlotPhotos(s).importFiles('p', [photo(1), photo(2)]);
      final reopened = AppStore(
        ObservationRepository(factory: s.repository.factory),
      );
      await reopened.init();
      expect(reopened.plotById('p')!.toMap(), plot.toMap());
      expect(reopened.photosForPlot('p').length, 2);
      expect(
        reopened.observations.singleWhere((o) => o.id == 'old').toMap(),
        old.toMap(),
      );
      expect(
        reopened.photosForPlot('p').first.photoBytes,
        await photo(2).readAsBytes(),
      );
      expect(
        reopened
            .photosForPlot('p')
            .every((o) => o.rank == IdentificationRank.undetermined),
        true,
      );
      await s.repository.close();
      await s.plotRepository.close();
      await reopened.repository.close();
      await reopened.plotRepository.close();
    },
  );
  test(
    'The species list follows confirmed photos; manual quantities survive deduplication and reidentification',
    () async {
      final s = await plotStore();
      await s.savePlot(
        example(
          species: [
            const PlotSpecies(
              name: 'Physcia aipolia',
              italicId: 1717,
              abundance: '15%',
            ),
          ],
        ),
      );
      await s.save(
        Observation(
          id: 'a',
          createdAt: stamp,
          plotId: 'p',
          taxonName: 'Physcia aipolia (updated authors)',
          taxonItalicId: 1717,
          rank: IdentificationRank.species,
        ),
      );
      await s.save(
        Observation(
          id: 'b',
          createdAt: stamp,
          plotId: 'p',
          taxonName: 'Peltigera canina',
          taxonItalicId: 222,
        ),
      );
      expect(s.speciesForPlot(s.plots.single).length, 1);
      expect(s.speciesForPlot(s.plots.single).single.abundance, '15%');
      final b = Observation.fromMap(
        s.observations.singleWhere((o) => o.id == 'b').toMap(),
      )..rank = IdentificationRank.species;
      await s.save(b);
      expect(s.speciesForPlot(s.plots.single).length, 2);
      b
        ..taxonName = 'Physcia aipolia'
        ..taxonItalicId = 1717;
      await s.save(b);
      expect(s.speciesForPlot(s.plots.single).length, 1);
      await s.delete(b);
      expect(s.speciesForPlot(s.plots.single).length, 1);
      expect(
        FieldAchievementIndex(plotTaxa)
            .progress(
              s.observations,
              additionalSpecies: s.plots.expand(
                (p) => p.species.map((s) => s.name),
              ),
            )
            .speciesCount,
        1,
      );
    },
  );
  test(
    'Gallery imports multiple photos, skips identical files and preserves partial successes',
    () async {
      final s = await plotStore();
      await s.savePlot(example());
      final picker = PlotPicker()
        ..files = [
          photo(1),
          photo(2),
          photo(1),
          XFile.fromData(Uint8List(0), name: 'empty.png'),
        ];
      final service = PlotPhotos(s, picker: picker);
      final result = await service.add('p');
      expect([result.saved, result.skipped, result.failed], [2, 1, 1]);
      expect(picker.metadata, false);
      expect(await s.plotRepository.pendingPhotoPlot(), 'p');
      picker.files = [photo(1), photo(2)];
      final retry = await service.add('p');
      expect([retry.saved, retry.skipped], [0, 2]);
      expect(await s.plotRepository.pendingPhotoPlot(), isNull);
      picker.files = [];
      expect((await service.add('p', camera: true)).saved, 0);
      expect(picker.source, ImageSource.camera);
      expect(s.photosForPlot('p').length, 2);
      picker.files = [photo(3)];
      expect((await service.add('p', camera: true)).saved, 1);
    },
  );
  test(
    'Android lost multi-photo recovery retains plot association without duplicate imports',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final s = await plotStore();
      await s.savePlot(example());
      await PlotPhotos(s).importFiles('p', [photo(1)]);
      await s.plotRepository.setPendingPhotoPlot('p');
      final picker = PlotPicker()
        ..lost = LostDataResponse(
          files: [photo(1), photo(2)],
          type: RetrieveType.image,
        );
      await PlotPhotos(s, picker: picker).recover();
      expect(s.photosForPlot('p').length, 2);
      expect(await s.plotRepository.pendingPhotoPlot(), isNull);
      expect(s.plotPhotoRecoveryNotice, contains('1 foto'));
    },
  );
  test(
    'Failed plot writes cannot change the in-memory or persisted original',
    () async {
      final repo = FailingPlots();
      final s = AppStore(
        ObservationRepository(factory: newIdbFactoryMemory()),
        plotRepository: repo,
      );
      await s.init();
      await s.savePlot(example());
      repo.fail = true;
      await expectLater(
        s.savePlot(
          FieldPlot.fromMap({...example().toMap(), 'name': 'Changed'}),
        ),
        throwsStateError,
      );
      expect(s.plots.single.name, 'Bosco · plot 01');
      expect((await repo.all()).single.name, 'Bosco · plot 01');
    },
  );
  test(
    'Map entries use plot positions live without relabelling them as photo GPS measurements',
    () async {
      final s = await plotStore();
      await s.savePlot(
        example(
          species: [const PlotSpecies(name: 'Physcia aipolia', italicId: 1717)],
        ),
      );
      await PlotPhotos(s).importFiles('p', [photo(1)]);
      final original = s.photosForPlot('p').single;
      expect(original.hasPosition, false);
      expect(s.mapObservations.length, 2);
      expect(s.mapObservations.every((o) => o.latitude == 45), true);
      expect(s.mapObservations.first.positionProvider, 'plot');
      await s.savePlot(
        FieldPlot.fromMap({...example().toMap(), 'latitude': 44}),
      );
      expect(s.mapObservations.first.latitude, 44);
      expect(original.latitude, isNull);
      original
        ..rank = IdentificationRank.species
        ..taxonName = 'Physcia aipolia'
        ..taxonItalicId = 1717;
      await s.save(original);
      expect(s.mapObservations.length, 1);
    },
  );
}
