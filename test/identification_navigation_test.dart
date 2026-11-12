import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:italicapp/data/identification_repository.dart';
import 'package:italicapp/data/italic_reference_repository.dart';
import 'package:italicapp/pages/identification_page.dart';
import 'package:italicapp/pages/italic_page.dart';
import 'package:italicapp/pages/general_keys_page.dart';
import 'package:italicapp/pages/settings_page.dart';
import 'plots_test.dart' as fixtures;
import 'package:italicapp/services/identification_engine.dart';
import 'package:italicapp/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secondaryKeys = [
    'open-species-key',
    'open-physcia-review',
    'open-character-matrix',
    'open-api-traits-matrix',
    'open-character-dictionary',
    'open-official-keys',
  ];

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(375, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('Phone: diary key entry keeps the general key without tools', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: DeterminationStartPage(repository: _Repository()),
      ),
    );
    await tester.pumpAndSettle();
    final primary = find.byKey(const ValueKey('open-general-keys'));
    expect(primary, findsOneWidget);
    expect(tester.getRect(primary).bottom, lessThan(844));
    for (final id in secondaryKeys) {
      expect(find.byKey(ValueKey(id)), findsNothing);
    }
    expect(find.text('Strumenti e dati'), findsNothing);
    expect(primary, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Auxiliary data failure does not hide or disable the general key',
    (tester) async {
      phone(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: DeterminationStartPage(repository: _Repository(fail: true)),
        ),
      );
      await tester.pumpAndSettle();
      final primary = find.byKey(const ValueKey('open-general-keys'));
      expect(tester.widget<ListTile>(primary).onTap, isNotNull);
      expect(find.text('Strumenti e dati'), findsNothing);
      expect(primary, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ITALIC: prominent key button is above search on a phone and opens identification',
    (tester) async {
      phone(tester);
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(body: ItalicPage()),
          ),
        );
        await ItalicReferenceRepository().load();
      });
      await tester.pumpAndSettle();
      final entry = find.byKey(const ValueKey('open-identification-keys'));
      final search = find.byKey(const ValueKey('italic-species-search'));
      expect(tester.widget(entry), isA<FilledButton>());
      expect(
        tester.getRect(entry).bottom,
        lessThan(tester.getRect(search).top),
      );
      expect(tester.getRect(entry).bottom, lessThan(844));
      await tester.runAsync(() async {
        await tester.tap(entry);
        await tester.pump();
        await Future<void>.delayed(const Duration(seconds: 1));
      });
      await tester.pumpAndSettle();
      expect(find.byType(GeneralKeysPage), findsOneWidget);
      expect(find.byType(DeterminationStartPage), findsNothing);
      expect(find.byKey(const ValueKey('open-general-keys')), findsNothing);
      expect(find.byKey(const ValueKey('open-species-key')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Supporting tools remain available on their dedicated page', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: DeterminationStartPage(
          repository: _Repository(),
          toolsOnly: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Strumenti e dati'), findsOneWidget);
    for (final id in secondaryKeys) {
      await tester.scrollUntilVisible(find.byKey(ValueKey(id)), 200);
      expect(find.byKey(ValueKey(id)), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('open-general-keys')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Settings opens the dedicated tools page', (tester) async {
    phone(tester);
    final store = (await tester.runAsync(fixtures.plotStore))!;
    addTearDown(store.repository.close);
    addTearDown(store.plotRepository.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: SettingsPage(store: store)),
      ),
    );
    await tester.pumpAndSettle();
    final entry = find.byKey(const ValueKey('settings-identification-tools'));
    await tester.scrollUntilVisible(entry, 250);
    await tester.ensureVisible(entry);
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(
      tester
          .widget<DeterminationStartPage>(find.byType(DeterminationStartPage))
          .toolsOnly,
      true,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

class _Repository extends IdentificationRepository {
  _Repository({this.fail = false}) {
    pilot = IdentificationKey.fromMap(
      jsonDecode(
        File('assets/italic/flavoparmelia_key.json').readAsStringSync(),
      ),
    );
  }
  final bool fail;
  @override
  Future<void> load() async {
    if (fail) throw StateError('Simulated auxiliary data failure');
  }
}
