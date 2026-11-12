import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:italicapp/widgets/app_startup.dart';
import 'package:italicapp/theme/app_theme.dart';

void main() {
  testWidgets(
    'The cover paints before initialization finishes and does not mount the diary early',
    (tester) async {
      final pending = Completer<void>();
      var initialized = false, built = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: AppStartup(
            initialize: () {
              initialized = true;
              return pending.future;
            },
            child: Builder(
              builder: (_) {
                built = true;
                return const Scaffold(body: Text('Diario pronto'));
              },
            ),
          ),
        ),
      );
      expect(initialized, true);
      expect(built, false);
      expect(find.byType(LichenOpening), findsOneWidget);
      expect(find.byKey(const ValueKey('startup-loading')), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      expect(built, false);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Diario pronto'), findsOneWidget);
      expect(find.byType(LichenOpening), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'A clean opening shows only ITALIC GO and enters the diary after about 2.6 seconds',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AppStartup(child: Scaffold(body: Text('Home'))),
        ),
      );
      expect(find.text('ITALIC GO'), findsOneWidget);
      expect(find.text('Il tuo diario dei licheni'), findsNothing);
      expect(find.byKey(const ValueKey('skip-opening')), findsNothing);
      expect(find.byType(Image), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 2200));
      expect(find.text('Home'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      expect(find.byType(LichenOpening), findsNothing);
    },
  );

  testWidgets(
    'The opening completes automatically and does not replay on a parent rebuild',
    (tester) async {
      late StateSetter update;
      var initialized = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return AppStartup(
                initialize: () async {
                  initialized++;
                },
                child: const Scaffold(body: Text('Home')),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(initialized, 1);
      expect(find.text('Home'), findsOneWidget);
      update(() {});
      await tester.pumpAndSettle();
      expect(find.byType(LichenOpening), findsNothing);
      expect(initialized, 1);
    },
  );

  testWidgets(
    'Initialization failure offers retry and never opens a partial diary',
    (tester) async {
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: AppStartup(
            initialize: () async {
              if (attempts++ == 0) throw StateError('unavailable');
            },
            child: const Scaffold(body: Text('Home')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('startup-error')), findsOneWidget);
      expect(find.text('Home'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('retry-startup')));
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      expect(attempts, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Reduced motion uses a static opening while waiting for the diary',
    (tester) async {
      final pending = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: AppStartup(
              initialize: () => pending.future,
              child: const Scaffold(body: Text('Home')),
            ),
          ),
        ),
      );
      expect(
        tester.widget<LichenOpening>(find.byType(LichenOpening)).motion.value,
        1,
      );
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(320, 640), const Size(844, 390)]) {
    testWidgets(
      'Opening fits $size with large text; late initialization after disposal is ignored',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final pending = Completer<void>();
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
              child: AppStartup(
                initialize: () => pending.future,
                child: const SizedBox(),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        pending.complete();
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
