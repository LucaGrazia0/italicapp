import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import '../app_store.dart';
import '../models/observation.dart';

class PlotPhotoResult {
  const PlotPhotoResult(this.saved, this.skipped, this.failed);
  final int saved, skipped, failed;
}

class PlotPhotos {
  PlotPhotos(this.store, {ImagePicker? picker})
    : picker = picker ?? ImagePicker();
  final AppStore store;
  final ImagePicker picker;
  Future<PlotPhotoResult> add(String plotId, {bool camera = false}) async {
    if (store.plotById(plotId) == null) {
      throw StateError('Plot non disponibile.');
    }
    await store.plotRepository.setPendingPhotoPlot(plotId);
    List<XFile> files;
    try {
      if (camera) {
        final file = await picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1800,
          imageQuality: 88,
          requestFullMetadata: false,
        );
        files = file == null ? [] : [file];
      } else {
        files = await picker.pickMultiImage(
          maxWidth: 1800,
          imageQuality: 88,
          requestFullMetadata: false,
        );
      }
    } catch (_) {
      await store.plotRepository.setPendingPhotoPlot(null);
      rethrow;
    }
    final result = await importFiles(plotId, files);
    if (result.failed == 0) {
      await store.plotRepository.setPendingPhotoPlot(null);
    }
    return result;
  }

  Future<PlotPhotoResult> importFiles(String plotId, List<XFile> files) async {
    if (store.plotById(plotId) == null) {
      throw StateError('Plot non disponibile.');
    }
    var saved = 0, skipped = 0, failed = 0;
    final known = {
      for (final o in store.observations.where(
        (o) => o.plotId == plotId && o.plotPhotoKey != null,
      ))
        o.plotPhotoKey!,
    };
    for (final file in files) {
      try {
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) throw StateError('Foto vuota');
        final key = sha256.convert(bytes).toString();
        if (known.contains(key)) {
          skipped++;
          continue;
        }
        final observation = Observation(
          id: 'plot-photo-$plotId-${DateTime.now().microsecondsSinceEpoch}-$saved',
          createdAt: DateTime.now(),
          photoBytes: bytes,
          photoName: file.name,
          plotId: plotId,
          plotPhotoKey: key,
        );
        await store.save(observation);
        known.add(key);
        saved++;
      } catch (_) {
        failed++;
      }
    }
    return PlotPhotoResult(saved, skipped, failed);
  }

  Future<void> recover() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    if (store.plotLoadError != null) return;
    try {
      final id = await store.plotRepository.pendingPhotoPlot();
      if (id == null || store.plotById(id) == null) return;
      final response = await picker.retrieveLostData();
      if (response.exception != null) {
        store.plotPhotoRecoveryNotice =
            'Alcune foto del plot non sono state recuperate. Riapri il plot e selezionale di nuovo.';
        return;
      }
      final result = await importFiles(id, response.files ?? []);
      if (result.failed == 0) {
        await store.plotRepository.setPendingPhotoPlot(null);
      }
      store.plotPhotoRecoveryNotice = result.failed > 0
          ? 'Alcune foto del plot non sono state recuperate. Riapri il plot e selezionale di nuovo.'
          : result.saved > 0
          ? 'Recuperate ${result.saved} foto nel plot.'
          : null;
    } catch (_) {
      store.plotPhotoRecoveryNotice =
          'Recupero foto del plot non completato. Riapri il plot e riprova dalla galleria.';
    }
  }
}
