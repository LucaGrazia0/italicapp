import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:italicapp/data/scientific_data.dart';
import 'package:italicapp/data/observation_repository.dart';
import 'package:italicapp/models/observation.dart';
import 'package:italicapp/services/data_updates.dart';
import 'package:italicapp/services/reconstructed_key.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<int> payload;
  late DataRelease release;
  setUpAll(() {
    final files = {
      for (final p in ScientificData.paths) p: File(p).readAsStringSync(),
    };
    final key = jsonDecode(files[ReconstructedKey.generalAsset]!) as Map;
    key['title'] = 'Edizione di prova aggiornata';
    files[ReconstructedKey.generalAsset] = jsonEncode(key);
    payload = utf8.encode(
      jsonEncode({'schemaVersion': 1, 'revision': 2026110401, 'files': files}),
    );
    release = DataRelease(
      revision: 2026110401,
      version: 'Edizione di prova',
      bytes: payload.length,
      sha256Hash: sha256.convert(payload).toString(),
      minimumAppBuild: 19,
      dataUrl: Uri.parse(
        'https://github.com/LucaGrazia0/italicapp/releases/download/test/italicapp-data.json',
      ),
    );
  });
  tearDown(() async {
    await ScientificData.reset();
    ReconstructedKey.clearCache();
  });
  test(
    'No published release is reported honestly and no download is attempted',
    () async {
      final updates = DataUpdates(
        client: MockClient((r) async => http.Response('', 404)),
      );
      expect(await updates.check(), isNull);
      updates.close();
    },
  );
  test('A damaged download is rejected before activation', () async {
    expect(
      () => DataUpdates.validate(payload.sublist(1), release),
      throwsFormatException,
    );
    expect(ScientificData.currentRevision, ScientificData.bundledRevision);
  });
  test(
    'A full verified update persists offline and historical keys and the diary remain intact',
    () async {
      final factory = newIdbFactoryMemory();
      await ScientificData.initialize(factory: factory);
      final repo = ObservationRepository(factory: factory);
      await repo.save(
        Observation(
          id: 'original',
          createdAt: DateTime.utc(2026, 11, 3),
          latitude: 45,
          longitude: 11,
          horizontalAccuracy: 3,
          notes: 'Diario da conservare',
        ),
      );
      final old = await ReconstructedKey.loadGeneral(
        revision: ScientificData.bundledRevision,
      );
      final updates = DataUpdates(
        client: MockClient((r) async => http.Response.bytes(payload, 200)),
      );
      await updates.install(release);
      expect(ScientificData.currentRevision, release.revision);
      final updated = await ReconstructedKey.loadGeneral();
      expect(updated.title, 'Edizione di prova aggiornata');
      expect(
        (await ReconstructedKey.loadGeneral(
          revision: ScientificData.bundledRevision,
        )).title,
        old.title,
      );
      expect((await repo.all()).single.notes, 'Diario da conservare');
      await ScientificData.reset();
      await ScientificData.initialize(factory: factory);
      expect(
        (await ReconstructedKey.loadGeneral()).title,
        'Edizione di prova aggiornata',
      );
      await repo.close();
      updates.close();
    },
  );
  test(
    'Incompatible app editions and untrusted manifests cannot replace local data',
    () async {
      var downloads = 0;
      final updates = DataUpdates(
        client: MockClient((r) async {
          downloads++;
          return http.Response('', 200);
        }),
      );
      final newer = DataRelease(
        revision: release.revision,
        version: release.version,
        bytes: release.bytes,
        sha256Hash: release.sha256Hash,
        dataUrl: release.dataUrl,
        minimumAppBuild: 999,
      );
      await expectLater(updates.install(newer), throwsStateError);
      expect(downloads, 0);
      expect(
        () => DataRelease.fromMap({
          'schemaVersion': 1,
          'bytes': 10,
          'dataUrl': 'http://example.com/data',
          'sha256': 'x',
        }),
        throwsFormatException,
      );
      updates.close();
    },
  );
}
