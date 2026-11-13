import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../data/inaturalist_upload_repository.dart';
import '../models/observation.dart';
import 'field_dataset.dart';
import 'inaturalist_auth.dart';
import 'inaturalist_photo.dart';

enum INaturalistPrivacy { private, obscured, open }

Map<String, Object?> inaturalistObservationPayload(
  Observation observation,
  FieldDataset dataset, {
  required bool includeGps,
  INaturalistPrivacy privacy = INaturalistPrivacy.private,
  String recordedBy = '',
  String identifiedBy = '',
}) {
  final o = dataset.effective(observation);
  // Coordinates go into native fields only, never into publicly visible notes
  // (even for private/obscured observations).
  final record = dataset
      .records(
        includeGps: false,
        recordedBy: recordedBy,
        identifiedBy: identifiedBy,
      )
      .where((r) => r['occurrenceID'] == 'urn:italicgo:occurrence:${o.id}')
      .first;
  if (includeGps && o.hasPosition) {
    // Altitude and provenance are retained in the Darwin Core notes; exact
    // coordinates stay in iNaturalist's native, privacy-controlled fields.
    record['minimumElevationInMeters'] = o.seaLevelAltitude;
    record['maximumElevationInMeters'] = o.seaLevelAltitude;
    record['coordinateUncertaintyInMeters'] = o.positionUncertaintyInMeters;
  }
  return {
    if (o.taxonName?.trim().isNotEmpty == true)
      'species_guess': o.taxonName!.trim(),
    // ITALIC IDs are not iNaturalist taxon IDs. The original determination is
    // retained verbatim; no fuzzy match is silently turned into a taxon_id.
    'observed_on_string':
        o.eventDate.toIso8601String() +
        (o.eventDate.isUtc ? '' : _offset(o.eventDate.timeZoneOffset)),
    'description': dataset.completeNotes(record),
    'geoprivacy': switch (privacy) {
      INaturalistPrivacy.private => 'private',
      INaturalistPrivacy.obscured => 'obscured',
      INaturalistPrivacy.open => null,
    },
    if (includeGps && o.hasPosition) ...{
      'latitude': o.latitude,
      'longitude': o.longitude,
      if (o.positionUncertaintyInMeters != null)
        'positional_accuracy': o.positionUncertaintyInMeters,
    },
  };
}

String _offset(Duration value) {
  final minutes = value.inMinutes.abs();
  return '${value.isNegative ? '-' : '+'}${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
}

class INaturalistUploadResult {
  const INaturalistUploadResult(this.id, {this.alreadySent = false});
  final int id;
  final bool alreadySent;
  Uri get url => Uri.parse('https://www.inaturalist.org/observations/$id');
}

class INaturalistUploader {
  INaturalistUploader({
    required this.auth,
    http.Client? client,
    INaturalistUploadRepository? repository,
    Future<Uint8List> Function(Uint8List)? preparePhoto,
  }) : client = client ?? http.Client(),
       repository = repository ?? INaturalistUploadRepository(),
       preparePhoto = preparePhoto ?? prepareINaturalistPhoto;
  final INaturalistAuth auth;
  final http.Client client;
  final INaturalistUploadRepository repository;
  final Future<Uint8List> Function(Uint8List) preparePhoto;
  static final _active = <String>{};
  static const _api = 'https://api.inaturalist.org/v1';

  Future<INaturalistUploadResult> send(
    Observation observation,
    Map<String, Object?> payload,
  ) async {
    await auth.load();
    final account = auth.session;
    if (account == null) {
      throw const INaturalistFailure('Collega prima iNaturalist.');
    }
    final key = '${account.userId}:${observation.id}';
    if (!_active.add(key)) {
      throw const INaturalistFailure('Invio già in corso.');
    }
    try {
      return await _send(observation, payload, key, account.userId);
    } finally {
      _active.remove(key);
    }
  }

  Future<INaturalistUploadResult> _send(
    Observation observation,
    Map<String, Object?> payload,
    String key,
    int userId,
  ) async {
    final bearer = await auth.bearer();
    final headers = {
      'Authorization': 'Bearer $bearer',
      'Accept': 'application/json',
    };
    final fingerprint = sha256
        .convert(utf8.encode(jsonEncode(payload)))
        .toString();
    var state = await repository.read(key);
    if (state?['complete'] == true) {
      return INaturalistUploadResult(
        state!['remoteId'] as int,
        alreadySent: true,
      );
    }
    if (state != null && state['fingerprint'] != fingerprint) {
      throw const INaturalistFailure(
        'È presente un invio incompleto con dati diversi. Riprendi con le opzioni originali.',
      );
    }
    // Prepare before creating a remote observation: an unreadable photo must
    // not leave an empty remote record. This copy has no old EXIF coordinates.
    final photo = observation.photoBytes;
    final prepared = photo?.isNotEmpty == true
        ? await preparePhoto(photo!)
        : null;
    if (auth.session?.userId != userId) {
      throw const INaturalistFailure('Account cambiato. Riprova.');
    }
    state ??= {
      'id': key,
      'uuid': _uuid(),
      'photoUuid': _uuid(),
      'fingerprint': fingerprint,
      'createAttempted': false,
      'photoAttempted': false,
    };
    await repository.write(state);
    Map? remote;
    if (state['createAttempted'] == true) {
      remote = await _find(
        state['remoteId'] ?? state['uuid'],
        headers,
        userId,
        state['uuid'],
      );
      if (remote == null) {
        // A lost POST response is ambiguous; never blindly repeat a write.
        throw const INaturalistFailure(
          'Invio non ancora confermato da iNaturalist. Riprova più tardi per evitare duplicati.',
        );
      }
    } else {
      state['createAttempted'] = true;
      await repository.write(state);
      final response = await client
          .post(
            Uri.parse('$_api/observations'),
            headers: {...headers, 'Content-Type': 'application/json'},
            body: jsonEncode({
              'observation': {...payload, 'uuid': state['uuid']},
            }),
          )
          .timeout(const Duration(seconds: 45));
      if (response.statusCode >= 400 && response.statusCode < 500) {
        state['createAttempted'] = false;
        await repository.write(state);
      }
      _check(response);
      remote = _result(response);
      _owner(remote, userId, state['uuid']);
    }
    final id = remote['id'] as int;
    state['remoteId'] = id;
    await repository.write(state);
    if (prepared != null) {
      final attached = (remote['observation_photos'] as List? ?? []).any(
        (p) => p is Map && p['uuid'] == state!['photoUuid'],
      );
      if (!attached) {
        if (state['photoAttempted'] == true) {
          throw INaturalistFailure(
            'La foto non è ancora confermata. Riprova più tardi. Osservazione iNaturalist: $id.',
          );
        }
        state['photoAttempted'] = true;
        await repository.write(state);
        final request =
            http.MultipartRequest('POST', Uri.parse('$_api/observation_photos'))
              ..headers.addAll(headers)
              ..fields['observation_photo[observation_id]'] = '$id'
              ..fields['observation_photo[uuid]'] = state['photoUuid'] as String
              ..files.add(
                http.MultipartFile.fromBytes(
                  'file',
                  prepared,
                  filename: 'Italic-Go.png',
                  contentType: MediaType('image', 'png'),
                ),
              );
        final response = await http.Response.fromStream(
          await client.send(request).timeout(const Duration(seconds: 90)),
        ).timeout(const Duration(seconds: 90));
        if (response.statusCode >= 400 && response.statusCode < 500) {
          state['photoAttempted'] = false;
          await repository.write(state);
        }
        _check(response);
        final attachedResult = _result(response);
        if (attachedResult['id'] is! int) {
          throw const INaturalistFailure(
            'Foto non confermata. Riprova più tardi.',
          );
        }
      }
    }
    state['complete'] = true;
    await repository.write(state);
    return INaturalistUploadResult(id);
  }

  Future<Map?> _find(
    Object? id,
    Map<String, String> headers,
    int userId,
    Object? uuid,
  ) async {
    final uri = id is int
        ? Uri.parse('$_api/observations/$id')
        : Uri.parse('$_api/observations').replace(
            queryParameters: {
              'uuid': '$uuid',
              'user_id': '$userId',
              'per_page': '1',
            },
          );
    final response = await client
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 25));
    if (response.statusCode == 404) return null;
    _check(response);
    final values = jsonDecode(response.body)['results'] as List;
    if (values.isEmpty) return null;
    final remote = values.single as Map;
    _owner(remote, userId, uuid);
    return remote;
  }

  void _owner(Map remote, int userId, Object? uuid) {
    if ((remote['user'] as Map?)?['id'] != userId ||
        remote['uuid'] != uuid ||
        remote['id'] is! int) {
      throw const INaturalistFailure(
        'Risposta iNaturalist non verificata. Nessun altro invio automatico.',
      );
    }
  }

  Map _result(http.Response response) {
    final decoded = jsonDecode(response.body);
    if (decoded is Map && decoded['results'] is List) {
      return (decoded['results'] as List).single as Map;
    }
    return decoded as Map;
  }

  void _check(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const INaturalistFailure(
          'Accesso non autorizzato. Ricollega iNaturalist.',
        );
      }
      if (response.statusCode == 429) {
        throw const INaturalistFailure(
          'iNaturalist è occupato. Riprova più tardi.',
        );
      }
      throw const INaturalistFailure(
        'iNaturalist non ha confermato l’invio. Riprova più tardi.',
      );
    }
  }
}

String _uuid() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
