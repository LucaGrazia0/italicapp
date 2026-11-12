import 'dart:async';
import 'package:flutter/material.dart';
import '../app_store.dart';
import '../data/achievement_notice_repository.dart';
import '../data/scientific_data.dart';
import '../pages/achievement_detail_page.dart';
import '../services/achievement_notices.dart';
import '../services/field_achievements.dart';

/// Lives under the navigator and outside the diary's tab, so a saved plot or
/// determination can celebrate on the page where the user is actually working.
class AchievementCelebrationHost extends StatefulWidget {
  const AchievementCelebrationHost({
    super.key,
    required this.store,
    required this.child,
    this.repository,
    this.loadIndex,
    this.controller,
  });
  final AppStore store;
  final AchievementNotices? controller;
  final Widget child;
  final AchievementNoticeRepository? repository;
  final Future<FieldAchievementIndex> Function()? loadIndex;
  @override
  State<AchievementCelebrationHost> createState() =>
      _AchievementCelebrationHostState();
}

class _AchievementCelebrationHostState extends State<AchievementCelebrationHost>
    with WidgetsBindingObserver {
  late final notices =
      widget.controller ??
      AchievementNotices(
        store: widget.store,
        repository:
            widget.repository ??
            AchievementNoticeRepository(
              factory: widget.store.repository.factory,
            ),
        loadIndex: widget.loadIndex ?? FieldAchievementIndex.load,
      );
  Timer? timer;
  bool showing = false;
  AppLifecycleState lifecycle = AppLifecycleState.resumed;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    notices.addListener(_schedule);
    notices.ready.then((_) => _schedule());
    ScientificData.changes.addListener(_refresh);
  }

  void _refresh() {
    notices.refreshIndex();
  }

  void _schedule() {
    timer?.cancel();
    if (!mounted ||
        showing ||
        lifecycle != AppLifecycleState.resumed ||
        notices.pending.isEmpty) {
      return;
    }
    // Let save callbacks, snackbars and return navigation finish first.
    timer = Timer(const Duration(milliseconds: 450), _present);
  }

  Future<void> _present() async {
    if (!mounted ||
        showing ||
        lifecycle != AppLifecycleState.resumed ||
        notices.pending.isEmpty) {
      return;
    }
    final navigator = Navigator.of(context);
    if (navigator.userGestureInProgress) {
      _schedule();
      return;
    }
    final batch = notices.pending;
    showing = true;
    try {
      await navigator.push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) =>
              AchievementDetailPage(achievements: batch, celebration: true),
        ),
      );
      if (mounted) await notices.acknowledge(batch.map((a) => a.target));
    } finally {
      showing = false;
      if (mounted) _schedule();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    lifecycle = state;
    _schedule();
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    ScientificData.changes.removeListener(_refresh);
    notices.removeListener(_schedule);
    if (widget.controller == null) notices.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
