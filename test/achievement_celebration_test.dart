import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:italicapp/app_store.dart';
import 'package:italicapp/data/achievement_notice_repository.dart';
import 'package:italicapp/data/italic_reference_repository.dart';
import 'package:italicapp/data/observation_repository.dart';
import 'package:italicapp/models/field_plot.dart';
import 'package:italicapp/models/observation.dart';
import 'package:italicapp/pages/achievement_detail_page.dart';
import 'package:italicapp/services/achievement_notices.dart';
import 'package:italicapp/services/achievement_profiles.dart';
import 'package:italicapp/services/field_achievements.dart';
import 'package:italicapp/theme/app_theme.dart';
import 'package:italicapp/widgets/achievement_celebration_host.dart';

final taxa = [
  for (var i = 0; i < 1000; i++)
    ItalicTaxon(
      scientificName:
          'Testus species${String.fromCharCode(97 + i ~/ 676)}${String.fromCharCode(97 + (i ~/ 26) % 26)}${String.fromCharCode(97 + i % 26)}',
      italicId: 10000 + i,
    ),
];
Observation record(String id, int species) => Observation(
  id: id,
  createdAt: DateTime(2026),
  rank: IdentificationRank.species,
  taxonName: taxa[species].scientificName,
);
FieldPlot plot(int species) => FieldPlot(
  id: 'plot',
  name: 'Rilievo',
  createdAt: DateTime(2026),
  sampledAt: DateTime(2026),
  species: taxa
      .take(species)
      .map((t) => PlotSpecies(name: t.scientificName))
      .toList(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppStore store;
  late FieldAchievementIndex index;
  setUp(() async {
    index = FieldAchievementIndex(taxa);
    store = AppStore(ObservationRepository(factory: newIdbFactoryMemory()));
  });
  tearDown(() async {
    await store.repository.close();
    await store.plotRepository.close();
  });

  AchievementNotices notices({
    AchievementNoticeRepository? repository,
    Future<FieldAchievementIndex> Function()? load,
  }) => AchievementNotices(
    store: store,
    repository:
        repository ??
        AchievementNoticeRepository(factory: store.repository.factory),
    loadIndex: load ?? () async => index,
  );

  test(
    'Every threshold gets one durable notice; synonyms, notes, deletion and re-addition do not repeat acknowledged celebrations',
    () async {
      await store.init();
      final n = notices();
      await n.ready;
      for (final a in fieldAchievements) {
        await store.savePlot(plot(a.target));
        await n.settled;
        expect(n.pending.map((p) => p.target), [a.target]);
        await n.acknowledge([a.target]);
      }
      await store.save(record('duplicate', 0));
      await n.settled;
      expect(n.pending, isEmpty);
      await store.savePlot(plot(0));
      await store.delete(store.observations.single);
      await n.settled;
      await store.savePlot(plot(1000));
      await n.settled;
      expect(n.pending, isEmpty);
      n.dispose();
      final reopened = notices();
      await reopened.ready;
      expect(reopened.pending, isEmpty);
      reopened.dispose();
    },
  );

  test(
    'A pending batch survives reopening; first installation does not replay old awards',
    () async {
      await store.init();
      await store.savePlot(plot(10));
      var n = notices();
      await n.ready;
      expect(n.pending, isEmpty);
      await store.savePlot(plot(1000));
      await n.settled;
      expect(n.pending.map((a) => a.target), [50, 100, 500, 1000]);
      n.dispose();
      n = notices();
      await n.ready;
      expect(n.pending.map((a) => a.target), [50, 100, 500, 1000]);
      await n.acknowledge([50, 100, 500, 1000]);
      n.dispose();
    },
  );

  test(
    'A save while the checklist loads is celebrated, and a correction cancels a pending award',
    () async {
      await store.init();
      final loading = Completer<FieldAchievementIndex>();
      final n = notices(load: () => loading.future);
      await store.save(record('first', 0));
      loading.complete(index);
      await n.settled;
      expect(n.pending.map((a) => a.target), [1]);
      await store.save(Observation(id: 'first', createdAt: DateTime(2026)));
      await n.settled;
      expect(n.pending, isEmpty);
      n.dispose();
    },
  );

  test(
    'Metadata storage failure never prevents an observation from being saved',
    () async {
      await store.init();
      final n = notices(repository: _Unavailable());
      await n.ready;
      await store.save(record('first', 0));
      await n.settled;
      expect(store.observations.single.taxonName, taxa.first.scientificName);
      expect(n.pending.map((a) => a.target), [1]);
      await n.acknowledge([1]);
      await store.save(record('again', 0));
      await n.settled;
      expect(n.pending, isEmpty);
      n.dispose();
    },
  );

  testWidgets(
    'A real save presents the animated page once and returns to the original page',
    (tester) async {
      await tester.runAsync(store.init);
      final repository = _MemoryNotices();
      final controller = (await tester.runAsync(() async {
        final value = notices(repository: repository);
        await value.ready;
        return value;
      }))!;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: AchievementCelebrationHost(
            store: store,
            repository: repository,
            controller: controller,
            loadIndex: () async => index,
            child: const Scaffold(body: Text('Pagina del diario')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AchievementDetailPage), findsNothing);
      await tester.runAsync(() async {
        await store.save(record('first', 0));
        await controller.settled;
        await Future<void>.delayed(const Duration(milliseconds: 550));
      });
      await tester.pump();
      expect(repository.state!.pending, contains(1));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('Un nuovo traguardo'), findsOneWidget);
      expect(find.text('Federico Cesi'), findsOneWidget);
      expect(find.byKey(const ValueKey('replay-medal')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('close-achievement')));
      await tester.pumpAndSettle();
      expect(find.text('Pagina del diario'), findsOneWidget);
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
        await controller.settled;
      });
      expect(repository.state!.seen, contains(1));
      await tester.runAsync(() async {
        await store.save(record('another-photo', 0));
        await controller.settled;
        await Future<void>.delayed(const Duration(milliseconds: 550));
      });
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byType(AchievementDetailPage), findsNothing);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'All six offline profiles fit a narrow phone with large text and reduced motion; one batch stays on one route',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(
              disableAnimations: true,
              textScaler: TextScaler.linear(1.6),
            ),
            child: const AchievementDetailPage(
              achievements: fieldAchievements,
              celebration: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < fieldAchievements.length; i++) {
        expect(
          find.text(achievementProfiles[fieldAchievements[i].target]!.name),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('replay-medal')), findsNothing);
        final next = find.byKey(const ValueKey('continue-achievement'));
        await tester.scrollUntilVisible(next, 350);
        await tester.ensureVisible(next);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (i < fieldAchievements.length - 1) {
          await tester.tap(next);
          await tester.pumpAndSettle();
        }
      }
    },
  );
}

class _MemoryNotices extends AchievementNoticeRepository {
  AchievementNoticeState? state;
  @override
  Future<AchievementNoticeState?> read() async => state;
  @override
  Future<void> write(AchievementNoticeState value) async {
    state = value;
  }

  @override
  Future<void> close() async {}
}

class _Unavailable extends AchievementNoticeRepository {
  @override
  Future<AchievementNoticeState?> read() async =>
      throw StateError('unavailable');
  @override
  Future<void> write(AchievementNoticeState value) async =>
      throw StateError('unavailable');
  @override
  Future<void> close() async {}
}
