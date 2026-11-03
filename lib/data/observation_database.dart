export 'observation_database_stub.dart'
    if (dart.library.io) 'observation_database_native.dart'
    if (dart.library.js_interop) 'observation_database_web.dart';
