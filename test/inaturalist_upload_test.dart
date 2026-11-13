import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:italicapp/app_store.dart';
import 'package:italicapp/data/inaturalist_upload_repository.dart';
import 'package:italicapp/data/observation_repository.dart';
import 'package:italicapp/models/observation.dart';
import 'package:italicapp/models/field_plot.dart';
import 'package:italicapp/pages/diary_page.dart';
import 'package:italicapp/pages/inaturalist_share_page.dart';
import 'package:italicapp/services/dataset_export_jobs.dart';
import 'package:italicapp/services/field_dataset.dart';
import 'package:italicapp/services/inaturalist_auth.dart';
import 'package:italicapp/services/inaturalist_photo.dart';
import 'package:italicapp/services/inaturalist_upload.dart';
import 'package:italicapp/widgets/inaturalist_connection.dart';
import 'field_update_test.dart' show samplePlot, samplePhoto;

class Credentials implements INaturalistCredentials {
  INaturalistSession? value;
  @override
  Future<INaturalistSession?> read() async => value;
  @override
  Future<void> write(INaturalistSession session) async => value = session;
  @override
  Future<void> clear() async => value = null;
}

class AppAuth extends FlutterAppAuth {
  AuthorizationTokenRequest? request;
  @override
  Future<AuthorizationTokenResponse> authorizeAndExchangeCode(
    AuthorizationTokenRequest request,
  ) async {
    this.request = request;
    return AuthorizationTokenResponse(
      'oauth',
      null,
      null,
      null,
      'Bearer',
      ['write'],
      null,
      null,
    );
  }
}

class NativeAuth extends INaturalistAuth {
  NativeAuth({super.clientId, super.client, super.credentials, super.appAuth});
  @override
  bool get supported => true;
}

class Fixture {
  Fixture() {
    credentials.value = const INaturalistSession(
      accessToken: 'oauth',
      userId: 42,
      login: 'test',
    );
    auth = INaturalistAuth(
      clientId: 'public-id',
      credentials: credentials,
      client: MockClient((request) async {
        expect(
          request.url.toString(),
          'https://www.inaturalist.org/users/api_token',
        );
        expect(request.headers['Authorization'], 'Bearer oauth');
        return http.Response('{"api_token":"jwt"}', 200);
      }),
    );
  }
  final credentials = Credentials();
  late final INaturalistAuth auth;
  final observation = samplePhoto('photo', located: true);
  final repository = INaturalistUploadRepository(
    factory: newIdbFactoryMemory(),
  );
  int creates = 0, photos = 0;
  bool loseCreate = false, losePhoto = false, photoAttached = false;
  Map<String, dynamic>? payload;
  String? photoUuid;
  http.Client get client => MockClient((request) async {
    expect(request.headers['Authorization'], 'Bearer jwt');
    if (request.method == 'POST' && request.url.path == '/v1/observations') {
      creates++;
      payload = jsonDecode(request.body)['observation'];
      if (loseCreate) throw TimeoutException('Test response lost');
      return result(remote);
    }
    if (request.method == 'GET') {
      if (request.url.path == '/v1/observations') {
        expect(request.url.queryParameters['uuid'], payload!['uuid']);
        expect(request.url.queryParameters['user_id'], '42');
      }
      return result(remote);
    }
    photos++;
    expect(request.url.path, '/v1/observation_photos');
    expect(
      latin1.decode(request.bodyBytes),
      contains('observation_photo[observation_id]'),
    );
    expect(latin1.decode(request.bodyBytes), contains('123'));
    // Multipart UUID is generated before the write and saved for reconciliation.
    final state = await repository.read('42:photo');
    photoUuid = state!['photoUuid'] as String;
    photoAttached = true;
    if (losePhoto) throw TimeoutException('Test photo response lost');
    return result({'id': 456, 'uuid': photoUuid});
  });
  Map<String, Object?> get remote => {
    'id': 123,
    'uuid': payload!['uuid'],
    'user': {'id': 42},
    'observation_photos': [
      if (photoAttached) {'id': 456, 'uuid': photoUuid},
    ],
  };
  http.Response result(Map value) => http.Response(
    jsonEncode({
      'results': [value],
    }),
    200,
  );
  INaturalistUploader uploader() => INaturalistUploader(
    auth: auth,
    repository: repository,
    client: client,
    preparePhoto: (bytes) async => bytes,
  );
  Map<String, Object?> get data => inaturalistObservationPayload(
    observation,
    FieldDataset(observations: [observation], plots: []),
    includeGps: true,
  );
}

class PreviewUploader extends INaturalistUploader {
  PreviewUploader(INaturalistAuth auth) : super(auth: auth);
  int calls = 0;
  Map<String, Object?>? payload;
  @override
  Future<INaturalistUploadResult> send(
    Observation observation,
    Map<String, Object?> payload,
  ) async {
    calls++;
    this.payload = payload;
    return const INaturalistUploadResult(123);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'An export job can cross the worker-isolate boundary with real photos and plot data',
    () async {
      final data = FieldDataset(
        observations: [samplePhoto('job')],
        plots: [samplePlot()],
      );
      final file = await buildDatasetExport(
        DatasetExportJob(data, forINaturalist: true, includeGps: true),
      );
      expect(file.name, 'Italic-Go-iNaturalist-DoLichens.zip');
      expect(file.bytes.take(2), [80, 75]);
    },
  );
  testWidgets(
    'Direct upload waits for explicit confirmation and cancellation sends nothing',
    (tester) async {
      final credentials = Credentials()
        ..value = const INaturalistSession(
          accessToken: 'oauth',
          userId: 42,
          login: 'test',
        );
      final auth = NativeAuth(clientId: 'public-id', credentials: credentials);
      await auth.load();
      final uploader = PreviewUploader(auth);
      final observation = samplePhoto('confirm', located: true);
      await tester.pumpWidget(
        MaterialApp(
          home: INaturalistSharePage(
            observations: [observation],
            auth: auth,
            uploader: uploader,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('inat-publish-confirm'));
      await tester.scrollUntilVisible(
        button,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('Conferma invio'), findsOneWidget);
      expect(uploader.calls, 0);
      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();
      expect(uploader.calls, 0);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Conferma invio'));
      await tester.pumpAndSettle();
      expect(uploader.calls, 1);
      expect(uploader.payload!['species_guess'], observation.taxonName);
      expect(uploader.payload!.keys, isNot(contains('latitude')));
      expect(
        find.text('Osservazione e foto inviate a iNaturalist.'),
        findsOneWidget,
      );
    },
  );
  test(
    'API payload uses the corrected position, uncertainty, date and name; no invented taxon ID',
    () {
      final o = samplePhoto('a').withMapPosition(
        -30.125,
        -70.5,
        uncertaintyInMeters: 82,
      )..seaLevelAltitude = 1500;
      final data = FieldDataset(observations: [o], plots: []);
      final payload = inaturalistObservationPayload(o, data, includeGps: true);
      expect(payload['species_guess'], o.taxonName);
      expect(payload['latitude'], -30.125);
      expect(payload['longitude'], -70.5);
      expect(payload['positional_accuracy'], 82);
      expect(
        payload['observed_on_string'],
        contains(o.eventDate.toIso8601String()),
      );
      expect(payload, isNot(contains('taxon_id')));
      expect(payload['geoprivacy'], 'private');
      expect(
        payload['description'],
        contains('scientificName: ${o.taxonName}'),
      );
      expect(payload['description'], isNot(contains('-30.125')));
      final hidden = inaturalistObservationPayload(o, data, includeGps: false);
      expect(hidden.keys, isNot(contains('latitude')));
      expect(hidden.keys, isNot(contains('positional_accuracy')));
    },
  );
  test(
    'Plot photos inherit only the documented plot date / point / uncertainty',
    () {
      final o = samplePhoto('a'),
          plot = FieldPlot.fromMap({
            ...samplePlot().toMap(),
            'coordinateUncertaintyInMeters': 50,
          });
      final payload = inaturalistObservationPayload(
        o,
        FieldDataset(observations: [o], plots: [plot]),
        includeGps: true,
      );
      expect(payload['latitude'], plot.latitude);
      expect(payload['positional_accuracy'], 50);
    },
  );
  test(
    'API creates one observation and attaches the photo, then returns the saved link',
    () async {
      final f = Fixture(), uploader = f.uploader();
      addTearDown(f.repository.close);
      final result = await uploader.send(f.observation, f.data);
      expect(
        result.url.toString(),
        'https://www.inaturalist.org/observations/123',
      );
      expect(f.payload!['latitude'], f.observation.latitude);
      expect(f.payload!['species_guess'], f.observation.taxonName);
      expect(f.creates, 1);
      expect(f.photos, 1);
      final again = await uploader.send(f.observation, f.data);
      expect(again.alreadySent, true);
      expect(f.creates, 1);
      expect(f.photos, 1);
    },
  );
  test(
    'Lost create response is reconciled with UUID without creating a duplicate',
    () async {
      final f = Fixture()..loseCreate = true;
      addTearDown(f.repository.close);
      final uploader = f.uploader();
      await expectLater(
        uploader.send(f.observation, f.data),
        throwsA(isA<TimeoutException>()),
      );
      final result = await uploader.send(f.observation, f.data);
      expect(result.id, 123);
      expect(f.creates, 1);
      expect(f.photos, 1);
    },
  );
  test(
    'Lost photo response is reconciled without attaching a second copy',
    () async {
      final f = Fixture()..losePhoto = true;
      addTearDown(f.repository.close);
      final uploader = f.uploader();
      await expectLater(
        uploader.send(f.observation, f.data),
        throwsA(isA<TimeoutException>()),
      );
      expect((await uploader.send(f.observation, f.data)).id, 123);
      expect(f.creates, 1);
      expect(f.photos, 1);
    },
  );
  test(
    'Unconfirmed create stays pending; an empty read never triggers another POST',
    () async {
      final f = Fixture()..loseCreate = true;
      addTearDown(f.repository.close);
      await expectLater(
        f.uploader().send(f.observation, f.data),
        throwsA(isA<TimeoutException>()),
      );
      var writes = 0;
      final retry = INaturalistUploader(
        auth: f.auth,
        repository: f.repository,
        preparePhoto: (b) async => b,
        client: MockClient((request) async {
          if (request.method != 'GET') writes++;
          return http.Response('{"results":[]}', 200);
        }),
      );
      await expectLater(
        retry.send(f.observation, f.data),
        throwsA(isA<INaturalistFailure>()),
      );
      expect(writes, 0);
    },
  );
  test('Unreadable photo prevents any remote write', () async {
    final f = Fixture();
    addTearDown(f.repository.close);
    final uploader = INaturalistUploader(
      auth: f.auth,
      client: f.client,
      repository: f.repository,
      preparePhoto: (_) async => throw const FormatException(),
    );
    await expectLater(
      uploader.send(f.observation, f.data),
      throwsA(isA<FormatException>()),
    );
    expect(f.creates, 0);
    expect(f.photos, 0);
  });
  test('Account journal is isolated; tokens are not written to it', () async {
    final f = Fixture();
    addTearDown(f.repository.close);
    await f.uploader().send(f.observation, f.data);
    final state = await f.repository.read('42:photo');
    expect(state!['remoteId'], 123);
    expect(state.toString(), isNot(contains('oauth')));
    expect(state.toString(), isNot(contains('jwt')));
    expect(await f.repository.read('43:photo'), isNull);
  });
  test(
    'OAuth uses official endpoints, a public client ID and no client secret',
    () async {
      final credentials = Credentials(), appAuth = AppAuth();
      final auth = NativeAuth(
        clientId: 'registered-public-id',
        credentials: credentials,
        appAuth: appAuth,
        client: MockClient(
          (r) async => r.url.host == 'www.inaturalist.org'
              ? http.Response('{"api_token":"jwt"}', 200)
              : http.Response('{"results":[{"id":42,"login":"test"}]}', 200),
        ),
      );
      await auth.connect();
      expect(appAuth.request!.clientSecret, isNull);
      expect(appAuth.request!.scopes, ['write']);
      expect(appAuth.request!.redirectUrl, INaturalistAuth.redirectUri);
      expect(
        appAuth.request!.serviceConfiguration!.authorizationEndpoint,
        'https://www.inaturalist.org/oauth/authorize',
      );
      expect(credentials.value!.userId, 42);
      await auth.disconnect();
      expect(credentials.value, isNull);
      expect(auth.session, isNull);
    },
  );
  test('An unregistered application never opens a fake login', () async {
    final appAuth = AppAuth();
    final auth = NativeAuth(
      clientId: '',
      credentials: Credentials(),
      appAuth: appAuth,
    );
    await expectLater(auth.connect(), throwsA(isA<INaturalistFailure>()));
    expect(appAuth.request, isNull);
  });
  testWidgets(
    'Unconfigured builds explain activation instead of showing an unusable login',
    (tester) async {
      final auth = NativeAuth(clientId: '', credentials: Credentials());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: INaturalistConnection(auth: auth)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('manca la registrazione'), findsOneWidget);
      expect(find.byKey(const ValueKey('inat-connect')), findsNothing);
    },
  );
  testWidgets(
    'A long diary builds only visible photo cards and can scroll to later records',
    (tester) async {
      final store = AppStore(
        ObservationRepository(factory: newIdbFactoryMemory()),
      );
      await tester.runAsync(store.init);
      store.observations = List.generate(
        500,
        (i) => Observation(
          id: 'o$i',
          createdAt: DateTime(2026, 10, 20),
          taxonName: 'Physcia $i',
          rank: IdentificationRank.species,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DiaryPage(store: store)),
        ),
      );
      await tester.pumpAndSettle();
      final built = find.byWidgetPredicate(
        (w) =>
            w is TextButton &&
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith(
              'diary-choose-species-',
            ),
      );
      expect(built.evaluate().length, lessThan(20));
      expect(
        find.byKey(const ValueKey('diary-choose-species-o499')),
        findsNothing,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('diary-choose-species-o20')),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.byKey(const ValueKey('diary-choose-species-o20')),
        findsOneWidget,
      );
    },
  );
  test(
    'Changing metadata reuses the photo allocation and leaves the original unchanged',
    () {
      final o = samplePhoto('copy'),
          changed = o.copy({'taxonName': 'New species'});
      expect(identical(changed.photoBytes, o.photoBytes), true);
      expect(o.taxonName, isNot('New species'));
    },
  );
  testWidgets(
    'Upload copy is decodable PNG without EXIF and never changes original bytes',
    (tester) async {
      final input = File('assets/branding/italic-go.webp').readAsBytesSync();
      final original = Uint8List.fromList(input);
      final output = await tester.runAsync(
        () => prepareINaturalistPhoto(input),
      );
      expect(output!.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      expect(input, original);
      expect(latin1.decode(output).contains('eXIf'), false);
    },
  );
}
