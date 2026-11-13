import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class INaturalistFailure implements Exception {
  const INaturalistFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class INaturalistSession {
  const INaturalistSession({
    required this.accessToken,
    required this.userId,
    required this.login,
    this.refreshToken,
    this.expiresAt,
  });
  final String accessToken, login;
  final int userId;
  final String? refreshToken;
  final DateTime? expiresAt;
  Map<String, Object?> toMap() => {
    'accessToken': accessToken,
    'userId': userId,
    'login': login,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt?.toIso8601String(),
  };
  factory INaturalistSession.fromMap(Map value) => INaturalistSession(
    accessToken: value['accessToken'] as String,
    userId: value['userId'] as int,
    login: value['login'] as String,
    refreshToken: value['refreshToken'] as String?,
    expiresAt: DateTime.tryParse(value['expiresAt']?.toString() ?? ''),
  );
}

abstract interface class INaturalistCredentials {
  Future<INaturalistSession?> read();
  Future<void> write(INaturalistSession session);
  Future<void> clear();
}

class SecureINaturalistCredentials implements INaturalistCredentials {
  static const _key = 'italicgo.inaturalist.session.v1';
  final _storage = const FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
    ),
  );
  @override
  Future<INaturalistSession?> read() async {
    final value = await _storage.read(key: _key);
    return value == null
        ? null
        : INaturalistSession.fromMap(jsonDecode(value) as Map);
  }

  @override
  Future<void> write(INaturalistSession session) =>
      _storage.write(key: _key, value: jsonEncode(session.toMap()));
  @override
  Future<void> clear() => _storage.delete(key: _key);
}

/// One public OAuth registration for Italic Go. Never embed a client secret.
/// AppAuth opens the system browser and checks state / PKCE before exchanging
/// the code. These callbacks are also registered in both native projects.
class INaturalistAuth extends ChangeNotifier {
  INaturalistAuth({
    String? clientId,
    http.Client? client,
    INaturalistCredentials? credentials,
    FlutterAppAuth? appAuth,
  }) : clientId =
           clientId ?? const String.fromEnvironment('INATURALIST_CLIENT_ID'),
       client = client ?? http.Client(),
       credentials = credentials ?? SecureINaturalistCredentials(),
       appAuth = appAuth ?? const FlutterAppAuth();
  static final shared = INaturalistAuth();
  static const redirectUri = 'it.italic.italicapp:/oauthredirect';
  static const service = AuthorizationServiceConfiguration(
    authorizationEndpoint: 'https://www.inaturalist.org/oauth/authorize',
    tokenEndpoint: 'https://www.inaturalist.org/oauth/token',
  );
  final String clientId;
  final http.Client client;
  final INaturalistCredentials credentials;
  final FlutterAppAuth appAuth;
  INaturalistSession? session;
  Future<void>? _loading;
  String? _jwt;
  DateTime? _jwtExpires;
  bool get configured => clientId.trim().isNotEmpty;
  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> load() =>
      _loading ??= _restore().catchError((Object error, StackTrace stack) {
        _loading = null;
        Error.throwWithStackTrace(error, stack);
      });
  Future<void> _restore() async {
    session = await credentials.read();
    notifyListeners();
  }

  Future<void> connect() async {
    if (!configured) {
      throw const INaturalistFailure(
        'Il collegamento richiede ancora la registrazione di Italic Go su iNaturalist.',
      );
    }
    if (!supported) {
      throw const INaturalistFailure(
        'Il collegamento è disponibile nelle app Android e iPhone.',
      );
    }
    await load().catchError((Object _) {});
    // No password, secret, embedded browser or access token in a URL.
    final response = await appAuth.authorizeAndExchangeCode(
      AuthorizationTokenRequest(
        clientId,
        redirectUri,
        serviceConfiguration: service,
        scopes: const ['write'],
      ),
    );
    final token = response.accessToken;
    if (token == null || token.isEmpty) {
      throw const INaturalistFailure('Accesso non completato. Riprova.');
    }
    final jwt = await _exchange(token);
    final me = await client
        .get(
          Uri.parse('https://api.inaturalist.org/v1/users/me'),
          headers: {'Authorization': 'Bearer $jwt'},
        )
        .timeout(const Duration(seconds: 25));
    if (me.statusCode != 200) {
      throw const INaturalistFailure(
        'Account non verificato. Riprova il collegamento.',
      );
    }
    final user = (jsonDecode(me.body)['results'] as List).single as Map;
    final connected = INaturalistSession(
      accessToken: token,
      userId: user['id'] as int,
      login: user['login'] as String,
      refreshToken: response.refreshToken,
      expiresAt: response.accessTokenExpirationDateTime,
    );
    await credentials.write(connected);
    session = connected;
    _jwt = jwt;
    _jwtExpires = DateTime.now().add(const Duration(hours: 23));
    notifyListeners();
  }

  Future<String> _exchange(String accessToken) async {
    final response = await client
        .get(
          Uri.parse('https://www.inaturalist.org/users/api_token'),
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw const INaturalistFailure(
        'Sessione scaduta. Ricollega iNaturalist.',
      );
    }
    final value = jsonDecode(response.body) as Map;
    final token = value['api_token'] as String?;
    if (token == null || token.isEmpty) {
      throw const INaturalistFailure('Accesso non disponibile. Riprova.');
    }
    return token;
  }

  Future<String> bearer() async {
    await load();
    var current = session;
    if (current == null) {
      throw const INaturalistFailure(
        'Collega prima il tuo account iNaturalist.',
      );
    }
    if (current.expiresAt != null &&
        !current.expiresAt!.isAfter(
          DateTime.now().add(const Duration(minutes: 1)),
        )) {
      if (current.refreshToken == null) {
        throw const INaturalistFailure(
          'Sessione scaduta. Ricollega iNaturalist.',
        );
      }
      final response = await appAuth.token(
        TokenRequest(
          clientId,
          redirectUri,
          refreshToken: current.refreshToken,
          serviceConfiguration: service,
        ),
      );
      final token = response.accessToken;
      if (token == null || token.isEmpty) {
        throw const INaturalistFailure(
          'Sessione scaduta. Ricollega iNaturalist.',
        );
      }
      current = INaturalistSession(
        accessToken: token,
        userId: current.userId,
        login: current.login,
        refreshToken: response.refreshToken ?? current.refreshToken,
        expiresAt: response.accessTokenExpirationDateTime,
      );
      await credentials.write(current);
      session = current;
      _jwt = null;
    }
    if (_jwt == null || _jwtExpires?.isAfter(DateTime.now()) != true) {
      _jwt = await _exchange(current.accessToken);
      _jwtExpires = DateTime.now().add(const Duration(hours: 23));
    }
    return _jwt!;
  }

  Future<void> disconnect() async {
    await credentials.clear();
    session = null;
    _jwt = null;
    _jwtExpires = null;
    notifyListeners();
  }
}
