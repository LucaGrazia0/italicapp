import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:italicapp/pages/italic_page.dart';
import 'package:italicapp/theme/app_theme.dart';
import 'package:italicapp/widgets/ecological_filters.dart';

void main() {
  testWidgets('Le classi selezionate si possono azzerare, incluso lo zero', (
    tester,
  ) async {
    final scales = <String, int>{};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, update) => Column(
                children: [
                  EcologicalFilters(
                    scales: scales,
                    photobiont: '',
                    reproduction: '',
                    onScaleChanged: (key, value) => update(() {
                      if (value == null) {
                        scales.remove(key);
                      } else {
                        scales[key] = value;
                      }
                    }),
                    onPhotobiontChanged: (_) {},
                    onReproductionChanged: (_) {},
                  ),
                  TextButton(
                    onPressed: () => update(scales.clear),
                    child: const Text('Azzera'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final dropdown = find.byKey(const ValueKey('scale-Poleotolerance-all'));
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Classe 0').last);
    await tester.pumpAndSettle();
    expect(scales, {'Poleotolerance': 0});
    final selected = find.byKey(const ValueKey('scale-Poleotolerance-0'));
    await tester.ensureVisible(selected);
    await tester.tap(selected);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Qualsiasi').last);
    await tester.pumpAndSettle();
    expect(scales, isEmpty);
    expect(
      find.byKey(const ValueKey('scale-Poleotolerance-all')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Filtri a larghezza telefono senza overflow', (tester) async {
    tester.view.physicalSize = const Size(375, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: _NarrowFilters(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<int>), findsNWidgets(6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Catalogo: classe ecologica filtra e classifica con dettagli', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: ItalicPage()),
        ),
      );
      await rootBundle.loadString('assets/italic/italic_checklist.json');
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(find.text('3588 taxa'), findsOneWidget);
    await tester.tap(find.text('Filtri ecologici'));
    await tester.pumpAndSettle();
    final acidity = find.byKey(const ValueKey('scale-pH of the substrata-all'));
    await tester.ensureVisible(acidity);
    await tester.tap(acidity);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Classe 1').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('taxa trovati'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('1199 taxa trovati'), findsOneWidget);
    expect(find.textContaining('3588 taxa trovati'), findsNothing);
    final mode = find.byKey(const ValueKey('compatibility-mode'));
    await tester.scrollUntilVisible(
      mode,
      -400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(mode);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('taxa trovati'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('3588 taxa trovati'), findsOneWidget);
    final evidence = find
        .textContaining('Riscontro sui dati valutabili: 100/100')
        .first;
    await tester.ensureVisible(evidence);
    await tester.tap(evidence);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('pH del substrato: classe 1 compresa'),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });
}

class _NarrowFilters extends StatelessWidget {
  const _NarrowFilters();
  @override
  Widget build(BuildContext context) => EcologicalFilters(
    scales: const {},
    photobiont: '',
    reproduction: '',
    onScaleChanged: (_, _) {},
    onPhotobiontChanged: (_) {},
    onReproductionChanged: (_) {},
  );
}
