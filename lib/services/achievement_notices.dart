import 'dart:async';
import 'package:flutter/foundation.dart';
import '../app_store.dart';
import '../data/achievement_notice_repository.dart';
import '../models/observation.dart';
import 'field_achievements.dart';

/// Serializes notice metadata independently of diary writes. A failed diary save
/// never notifies AppStore and therefore cannot award a new celebration.
class AchievementNotices extends ChangeNotifier {
  AchievementNotices({
    required this.store,
    required this.repository,
    required this.loadIndex,
  }) {
    final observations = store.observations
        .map(
          (o) => Observation(
            id: o.id,
            createdAt: o.createdAt,
            rank: o.rank,
            taxonName: o.taxonName,
          ),
        )
        .toList();
    final names = _plotNames.toList();
    store.addListener(_changed);
    ready = _enqueue(() => _initialize(observations, names));
  }
  final AppStore store;
  final AchievementNoticeRepository repository;
  final Future<FieldAchievementIndex> Function() loadIndex;
  late final Future<void> ready;
  Future<void> _work = Future.value();
  Future<void> get settled => _work;
  bool _disposed = false;
  FieldAchievementIndex? _index;
  AchievementNoticeState? _state;
  List<Observation>? _baseline;
  List<String>? _baselineNames;
  Iterable<String> get _plotNames =>
      store.plots.expand((p) => p.species.map((s) => s.name));
  List<FieldAchievement> get pending => fieldAchievements
      .where((a) => _state?.pending.contains(a.target) ?? false)
      .toList();

  Future<void> _enqueue(Future<void> Function() action) {
    _work = _work
        .then((_) async {
          if (!_disposed) await action();
        })
        .catchError((Object _) {
          // Optional celebrations must not interrupt saving or opening the diary.
        });
    return _work;
  }

  Future<void> _initialize(
    List<Observation> observations,
    List<String> names,
  ) async {
    _baseline = observations;
    _baselineNames = names;
    _index = await loadIndex();
    if (_disposed) return;
    try {
      _state = await repository.read();
    } catch (_) {
      /* Use the session ledger. */
    }
    if (_state == null) {
      // Existing achievements remain accessible, without a burst of old popups
      // when this feature is installed for the first time.
      final baseline = _index!.progress(observations, additionalSpecies: names);
      _state = AchievementNoticeState(
        seen: fieldAchievements.where(baseline.unlocked).map((a) => a.target),
      );
      await _persist();
    }
    await _evaluate();
  }

  Future<void> _persist() async {
    try {
      await repository.write(_state!);
    } catch (_) {
      /* Keep the in-memory ledger and the diary usable. */
    }
  }

  void _changed() => _enqueue(() async {
    if (_index == null || _state == null) {
      await _initialize(_baseline ?? [], _baselineNames ?? []);
    } else {
      await _evaluate();
    }
  });
  Future<void> refreshIndex() => _enqueue(() async {
    _index = await loadIndex();
    if (_state != null) await _evaluate();
  });
  Future<void> _evaluate() async {
    if (_disposed) return;
    final progress = _index!.progress(
      store.observations,
      additionalSpecies: _plotNames,
    );
    final eligible = fieldAchievements
        .where(progress.unlocked)
        .map((a) => a.target)
        .toSet();
    final next = eligible.difference(_state!.seen);
    if (setEquals(next, _state!.pending)) return;
    _state = AchievementNoticeState(seen: _state!.seen, pending: next);
    await _persist();
    if (!_disposed) notifyListeners();
  }

  Future<void> acknowledge(Iterable<int> targets) => _enqueue(() async {
    if (_state == null) return;
    final acknowledged = targets.toSet();
    _state = AchievementNoticeState(
      seen: {..._state!.seen, ...acknowledged},
      pending: _state!.pending.difference(acknowledged),
    );
    await _persist();
    if (!_disposed) notifyListeners();
  });
  @override
  void dispose() {
    _disposed = true;
    store.removeListener(_changed);
    unawaited(_work.whenComplete(repository.close));
    super.dispose();
  }
}
