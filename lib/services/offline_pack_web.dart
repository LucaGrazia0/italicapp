import 'dart:convert';
import 'dart:js_interop';

@JS('italicOfflineStatus')
external JSPromise<JSString> _status();
@JS('italicOfflinePrepare')
external JSPromise<JSString> _prepare();
@JS('italicOfflineProgress')
external JSString _progress();

const offlinePackSupported = true;
Future<Map<String, dynamic>> offlinePackStatus() async =>
    Map<String, dynamic>.from(
      jsonDecode((await _status().toDart).toDart) as Map,
    );
Future<Map<String, dynamic>> prepareOfflinePack() async =>
    Map<String, dynamic>.from(
      jsonDecode((await _prepare().toDart).toDart) as Map,
    );
double? offlinePackProgress() =>
    (jsonDecode(_progress().toDart)['progress'] as num?)?.toDouble();
