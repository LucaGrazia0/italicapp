import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:italicapp/data/identification_repository.dart';
import 'package:italicapp/data/original_key_repository.dart';
import 'package:italicapp/pages/identification_page.dart';
import 'package:italicapp/pages/original_key_page.dart';
import 'package:italicapp/theme/app_theme.dart';
import 'original_keys_test.dart' as sample;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late OriginalKeyArchive bundled;
  late String longest;
  setUpAll(() async {
    bundled = OriginalKeyArchive.fromMap(
      jsonDecode(File(OriginalKeyArchive.asset).readAsStringSync()) as Map,
    );
    final labels =
        bundled.keys.values
            .expand((k) => k.nodes.values)
            .expand((n) => n.choices)
            .map((c) => c.label)
            .toList()
          ..sort((a, b) => b.length.compareTo(a.length));
    longest = labels.first;
    final font = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('KEY_SCREENSHOTS')) return;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('capture')),
      );
      final rendered = await boundary.toImage(pixelRatio: 2);
      final png = await rendered.toByteData(format: ui.ImageByteFormat.png);
      rendered.dispose();
      final dir = Directory('reports/ui-original-keys')
        ..createSync(recursive: true);
      File('${dir.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  }

  Future<void> showPage(
    WidgetTester tester,
    Widget page,
    Size size,
    double scale,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('capture'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: page,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final scale in [1.0, 1.7, 2.0]) {
    testWidgets(
      'Longest published condition fits its card at 320 px and text scale $scale',
      (tester) async {
        final raw = sample.fixture();
        raw['nodes'][0]['choices'][0]['label'] = longest;
        await showPage(
          tester,
          OriginalKeyPage(
            entry: sample.entry,
            archive: Future.value(sample.archive(raw)),
            reference: const [],
          ),
          const Size(320, 740),
          scale,
        );
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('original-choice-0')),
          160,
        );
        await tester.pumpAndSettle();
        final card = tester.getRect(
          find.byKey(const ValueKey('original-choice-0')),
        );
        final text = tester.getRect(find.text(longest));
        expect(card.contains(text.topLeft), isTrue);
        expect(card.contains(text.bottomRight), isTrue);
        expect(text.width, lessThan(card.width));
        expect(tester.takeException(), isNull);
        await capture(tester, 'long-condition-${scale}x');
      },
    );
  }

  testWidgets(
    'Real Peltigera route and candidates remain readable on a phone',
    (tester) async {
      await showPage(
        tester,
        OriginalKeyPage(
          entry: sample.entry,
          archive: Future.value(bundled),
          reference: const [],
        ),
        const Size(390, 844),
        1,
      );
      await capture(tester, 'peltigera-start');
      await tester.tap(find.byKey(const ValueKey('original-choice-0')));
      await tester.pumpAndSettle();
      final title = tester.getRect(find.text('Bivio 2'));
      expect(title.top, greaterThanOrEqualTo(50));
      expect(title.bottom, lessThan(844 / 2));
      await capture(tester, 'peltigera-next');
      await tester.tap(
        find.byKey(const ValueKey('original-key-candidates-toolbar')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('taxa nei rami rimasti'), findsOneWidget);
      expect(find.byTooltip('Chiudi'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'peltigera-candidates');
    },
  );

  testWidgets('Long species names and descriptions fit at doubled text size', (
    tester,
  ) async {
    final raw = sample.fixture();
    raw['nodes'][0]['choices'][0] = {
      'label': 'Condition',
      'name':
          'Peltigera exceptionally-long species name (Original author) Another author',
      'description': List.filled(
        10,
        'Original description of the species.',
      ).join(' '),
    };
    // Node 2 is deliberately absent from this one-step fixture.
    raw['nodes'] = [raw['nodes'][0]];
    await showPage(
      tester,
      OriginalKeyPage(
        entry: sample.entry,
        archive: Future.value(sample.archive(raw)),
        reference: const [],
      ),
      const Size(320, 740),
      2,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('original-choice-0')),
      200,
    );
    await tester.tap(find.byKey(const ValueKey('original-choice-0')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Peltigera exceptionally-long'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture(tester, 'terminal-large-text');
  });

  testWidgets('Catalogue stays scrollable with enlarged text and keyboard', (
    tester,
  ) async {
    final longEntry = GenusKey(
      genus: 'Peltigera',
      name:
          'Peltigera and other genera sharing a very long original family key title',
      url: sample.entry.url,
    );
    await showPage(
      tester,
      OfficialKeysPage(entries: [longEntry, sample.entry]),
      const Size(320, 740),
      1.7,
    );
    await capture(tester, 'catalogue-large-text');
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.tap(find.byKey(const ValueKey('genus-key-search')));
    await tester.enterText(
      find.byKey(const ValueKey('genus-key-search')),
      'Peltigera',
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text(longEntry.name),
      100,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(tester.takeException(), isNull);
    final label = tester.getRect(find.text(longEntry.name));
    final button = tester.getRect(
      find.ancestor(
        of: find.text(longEntry.name),
        matching: find.byType(TextButton),
      ),
    );
    expect(button.contains(label.topLeft), isTrue);
    expect(button.contains(label.bottomRight), isTrue);
  });

  testWidgets('Full source sheets scroll at doubled text size', (tester) async {
    await showPage(
      tester,
      OriginalKeyPage(
        entry: sample.entry,
        archive: Future.value(sample.archive(sample.fixture())),
        reference: const [],
      ),
      const Size(320, 740),
      2,
    );
    await tester.tap(find.byTooltip('Altre opzioni'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Testo completo · offline').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Bivio 2'),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('original-key-sheet-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Bivio 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture(tester, 'full-text-large');
  });
}
