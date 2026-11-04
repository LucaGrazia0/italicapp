import 'scientific_data.dart';

/// Parsed scientific models are shared, but never across different editions.
class RevisionCache<T> {
  RevisionCache() {
    ScientificData.changes.addListener(clear);
  }
  final _values = <int, Future<T>>{};
  void clear() => _values.clear();
  Future<T> load(Future<T> Function(int) read, {int? revision}) async {
    await ScientificData.initialize();
    final key = revision ?? ScientificData.currentRevision;
    if (_values.containsKey(key)) return _values[key]!;
    if (_values.length >= 2) _values.remove(_values.keys.first);
    final future = (() async {
      try {
        return await read(key);
      } catch (_) {
        _values.remove(key);
        rethrow;
      }
    })();
    _values[key] = future;
    return future;
  }
}
