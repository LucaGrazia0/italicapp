import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:italicapp/pages/settings_page.dart';
import 'package:italicapp/pages/share_results_page.dart';
import 'package:italicapp/pages/dataset_export_page.dart';
import 'package:italicapp/pages/inaturalist_share_page.dart';
import 'package:italicapp/widgets/data_updates_card.dart';
import 'package:italicapp/widgets/offline_card.dart';
import 'package:italicapp/data/scientific_data.dart';
import 'package:italicapp/services/data_updates.dart';
import 'package:italicapp/theme/app_theme.dart';
import 'plots_test.dart' show plotStore;
import 'field_update_test.dart' show samplePlot, samplePhoto;

class Updates extends DataUpdates {
  int checks = 0, installs = 0;
  bool fail = false;
  DataRelease? release;
  @override
  Future<DataRelease?> check() async {
    checks++;
    if (fail) throw StateError('Offline');
    return release;
  }

  @override
  Future<void> install(
    DataRelease release, {
    void Function(double)? progress,
  }) async {
    installs++;
    progress?.call(1);
  }
}

void main() {
  testWidgets(
    'Settings starts compact; offline information and tools stay behind the collapsed section',
    (tester) async {
      final store = (await tester.runAsync(plotStore))!;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: SettingsPage(store: store)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-sharing')), findsOneWidget);
      expect(find.text('Controlla aggiornamenti'), findsOneWidget);
      expect(find.text('Uso senza connessione'), findsNothing);
      expect(find.byType(OfflineCard), findsNothing);
      expect(find.text('Strumenti e dati'), findsNothing);
      await tester.tap(find.text('Dati e archiviazione'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('settings-identification-tools')),
        findsOneWidget,
      );
      expect(find.byType(OfflineCard), findsOneWidget);
      await tester.tap(find.text('Dati e archiviazione'));
      await tester.pumpAndSettle();
      expect(find.text('Strumenti e dati'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Large sharing choices lead to the export options or to the effective plot observations',
    (tester) async {
      final store = (await tester.runAsync(plotStore))!;
      await tester.runAsync(() async {
        await store.savePlot(samplePlot());
        await store.save(samplePhoto('sharing'));
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: SettingsPage(store: store)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-sharing')));
      await tester.pumpAndSettle();
      expect(find.byType(ShareResultsPage), findsOneWidget);
      final export = find.byKey(const ValueKey('sharing-export'));
      final inat = find.byKey(const ValueKey('sharing-inaturalist'));
      expect(tester.getSize(export).height, greaterThanOrEqualTo(132));
      expect(tester.getSize(inat).height, greaterThanOrEqualTo(132));
      await tester.tap(export);
      await tester.pumpAndSettle();
      expect(find.byType(DatasetExportPage), findsOneWidget);
      expect(find.text('Excel .xlsx'), findsOneWidget);
      expect(find.text('CSV'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(inat);
      await tester.pumpAndSettle();
      final page = tester.widget<INaturalistSharePage>(
        find.byType(INaturalistSharePage),
      );
      expect(page.dataset!.plots.length, store.filteredPlots.length);
      expect(page.observations.length, store.filteredObservations.length);
      for (final o in page.observations) {
        final original = store.observations.singleWhere((v) => v.id == o.id);
        final effective = page.dataset!.effective(original);
        expect(o.latitude, effective.latitude);
        expect(o.eventDate, effective.eventDate);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Compact updates still checks, offers a compatible package and installs only on a second tap',
    (tester) async {
      final updates = Updates()
        ..release = DataRelease(
          revision: ScientificData.currentRevision + 1,
          version: 'Edizione di prova',
          bytes: 1024,
          sha256Hash: '0' * 64,
          dataUrl: Uri.parse(
            'https://github.com/LucaGrazia0/italicapp/releases/download/test/data.json',
          ),
          minimumAppBuild: DataUpdates.appBuild,
        );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DataUpdatesCard(compact: true, updates: updates),
          ),
        ),
      );
      expect(find.text('Aggiornamenti ITALIC'), findsNothing);
      expect(find.text('Scarica dati offline'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('check-data-updates')));
      await tester.pumpAndSettle();
      expect(updates.checks, 1);
      expect(updates.installs, 0);
      expect(find.text('Scarica dati offline'), findsOneWidget);
      await tester.tap(find.text('Scarica dati offline'));
      await tester.pumpAndSettle();
      expect(updates.installs, 1);
      expect(
        find.textContaining('Dati aggiornati e disponibili offline'),
        findsOneWidget,
      );
    },
  );

  testWidgets('An offline update failure is visible and can be retried', (
    tester,
  ) async {
    final updates = Updates()..fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DataUpdatesCard(compact: true, updates: updates)),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('check-data-updates')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Aggiornamento non completato'), findsOneWidget);
    updates.fail = false;
    await tester.tap(find.byKey(const ValueKey('check-data-updates')));
    await tester.pumpAndSettle();
    expect(updates.checks, 2);
    expect(find.textContaining('Non sono ancora pubblicati'), findsOneWidget);
  });

  testWidgets('The two sharing buttons fit a small phone with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = (await tester.runAsync(plotStore))!;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(
            ctx,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: ShareResultsPage(store: store),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Esporta dati'), findsOneWidget);
    expect(find.text('Condividi con iNaturalist'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
