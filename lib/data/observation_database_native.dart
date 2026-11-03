import 'package:idb_shim/idb_io.dart';
import 'package:path_provider/path_provider.dart';

Future<IdbFactory>? _loading;

/// File-backed storage in Android's private app data, never a temporary cache.
Future<IdbFactory> observationDatabaseFactory() => _loading ??= _load();
Future<IdbFactory> _load() async {
  try {
    final directory = await getApplicationSupportDirectory();
    return nativeDatabaseFactoryAt(directory.path);
  } catch (_) {
    _loading = null;
    rethrow;
  }
}

IdbFactory nativeDatabaseFactoryAt(String directory) =>
    getIdbFactoryPersistent(directory);
