import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:italicapp/data/italic_api_traits_repository.dart';
import 'package:italicapp/data/italic_reference_repository.dart';
import 'package:italicapp/pages/italic_api_traits_page.dart';

void main() {
  late Map source;
  late List<ItalicTaxon> reference;
  late ApiTraitsMatrix matrix;
  setUpAll(() {
    final raw =
        jsonDecode(
              File('reports/italic_api_traits/matrix.json').readAsStringSync(),
            )
            as Map;
    // Fixed local response snapshots keep these tests independent of download size.
    final checklist =
        (jsonDecode(
                  File(
                    'assets/italic/italic_checklist.json',
                  ).readAsStringSync(),
                )['taxa']
                as List)
            .cast<Map>();
    final ids = {1, 3323, 978, 1581, 1717, 1718, 1719, 2594};
    reference = checklist
        .where((r) => ids.contains(r['italicId']))
        .map((r) => ItalicTaxon.fromMap(Map<String, dynamic>.from(r)))
        .toList();
    source = jsonDecode(jsonEncode(raw)) as Map;
    source['requestedTaxa'] = reference.length;
    source['taxa'] = (source['taxa'] as List)
        .where((r) => ids.contains(r['italicId']))
        .toList();
    matrix = ApiTraitsMatrix.fromMap(source, reference);
  });

  Map changed() => jsonDecode(jsonEncode(source)) as Map;

  test(
    'Binary state zeros, missing values and specific conflicts remain distinct',
    () {
      final row = matrix.taxa.singleWhere((r) => r.taxon.italicId == 1717);
      expect(row.values['apothecia_lecanorine'], 1);
      expect(row.values['ascocarps_perithecioid'], 0);
      expect(row.values['ascocarps_present'], 1);
      expect(row.conflicts.any((c) => c.concerns('cortex_k_red')), isTrue);
      expect(
        row.conflicts.any((c) => c.concerns('growth_form_foliose')),
        isFalse,
      );
      final raw = changed();
      (raw['taxa'][0]['cells'] as Map)['growth_form_foliose'] = null;
      final missing = ApiTraitsMatrix.fromMap(raw, reference);
      expect(missing.taxa.first.values['growth_form_foliose'], isNull);
      expect(missing.recordedCells, matrix.recordedCells - 1);
    },
  );

  test(
    'Wrong taxon, duplicate row, incomplete coverage or provenance rejects data',
    () {
      final renamed = changed();
      renamed['taxa'][0]['apiName'] = 'A different species';
      expect(
        () => ApiTraitsMatrix.fromMap(renamed, reference),
        throwsFormatException,
      );
      final duplicate = changed();
      duplicate['taxa'][1] = duplicate['taxa'][0];
      expect(
        () => ApiTraitsMatrix.fromMap(duplicate, reference),
        throwsFormatException,
      );
      final short = changed();
      (short['taxa'] as List).removeLast();
      expect(
        () => ApiTraitsMatrix.fromMap(short, reference),
        throwsFormatException,
      );
      final provenance = changed();
      provenance['taxa'][0]['source']['url'] = 'https://example.org/data';
      expect(
        () => ApiTraitsMatrix.fromMap(provenance, reference),
        throwsFormatException,
      );
    },
  );

  test('Invalid binary values never turn into false', () {
    for (final value in [true, '1', 2, -1, 1.0]) {
      final raw = changed();
      raw['taxa'][0]['cells']['growth_form_foliose'] = value;
      expect(
        () => ApiTraitsMatrix.fromMap(raw, reference),
        throwsFormatException,
      );
    }
  });

  test(
    'Changed description keeps API values and signals a stale comparison',
    () {
      final changedReference = reference
          .map(
            (t) => t.italicId == 1717
                ? ItalicTaxon(
                    italicId: t.italicId,
                    scientificName: t.scientificName,
                    description:
                        'A revised description without the old quotation.',
                  )
                : t,
          )
          .toList();
      final result = ApiTraitsMatrix.fromMap(source, changedReference);
      final row = result.taxa.singleWhere((r) => r.taxon.italicId == 1717);
      expect(row.descriptionChanged, isTrue);
      expect(row.needsComparison, isTrue);
      expect(row.conflicts, isEmpty);
      expect(row.values['growth_form_foliose'], 1);
    },
  );

  test(
    'Complete asset covers every local taxon and preserves null API values',
    () {
      final allReference =
          (jsonDecode(
                    File(
                      'assets/italic/italic_checklist.json',
                    ).readAsStringSync(),
                  )['taxa']
                  as List)
              .cast<Map>()
              .map((r) => ItalicTaxon.fromMap(Map<String, dynamic>.from(r)))
              .toList();
      final allSource =
          jsonDecode(File(ItalicApiTraitsRepository.asset).readAsStringSync())
              as Map;
      final all = ApiTraitsMatrix.fromMap(allSource, allReference);
      expect(all.taxa.length, 3588);
      expect(all.characters.length, 31);
      expect(allSource['errors'], isEmpty);
      final missing = (allSource['taxa'] as List).fold<int>(
        0,
        (sum, row) =>
            sum + (row['cells'] as Map).values.where((v) => v == null).length,
      );
      expect(all.recordedCells + missing, 3588 * 31);
      expect(all.sorediaIndications, 516);
      expect(all.isidiaIndications, 130);
      final emptyRows = all.taxa.where(
        (r) => r.values.values.every((v) => v == null),
      );
      expect(emptyRows, isNotEmpty);
      expect(emptyRows.every((r) => r.needsComparison), isTrue);
      // An empty response may omit its warning; absence still is not inferred.
      expect(emptyRows.any((r) => r.warning.isEmpty), isTrue);
    },
  );

  test(
    'Reproduction indications retain broad meaning, source and unknown states',
    () {
      final adscendens = matrix.taxa.singleWhere(
        (r) => r.taxon.italicId == 1717,
      );
      final aipolia = matrix.taxa.singleWhere((r) => r.taxon.italicId == 1718);
      final saxatilis = matrix.taxa.singleWhere(
        (r) => r.taxon.italicId == 1581,
      );
      expect(adscendens.values['reproduction_soredia_or_similar'], 1);
      expect(adscendens.values['reproduction_isidia_or_similar'], isNull);
      expect(aipolia.values['reproduction_soredia_or_similar'], isNull);
      expect(aipolia.values['reproduction_isidia_or_similar'], isNull);
      expect(saxatilis.values['reproduction_isidia_or_similar'], 1);
      expect(saxatilis.reproductionEvidence!['quote'], contains('isidia-like'));
      final raw = changed();
      final row = (raw['taxa'] as List).singleWhere(
        (r) => r['italicId'] == 1717,
      );
      row['cells']['reproduction_soredia_or_similar'] = 0;
      expect(
        () => ApiTraitsMatrix.fromMap(raw, reference),
        throwsFormatException,
      );
      row['cells']['reproduction_soredia_or_similar'] = 1;
      row['reproductionEvidence']['quote'] = 'An outdated statement';
      final stale = ApiTraitsMatrix.fromMap(
        raw,
        reference,
      ).taxa.singleWhere((r) => r.taxon.italicId == 1717);
      expect(stale.reproductionChanged, isTrue);
      expect(stale.values['reproduction_soredia_or_similar'], isNull);
      expect(stale.values['growth_form_foliose'], 1);
    },
  );

  testWidgets(
    'Reproduction group shows local source and no automatic organ confirmation',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(home: ItalicApiTraitsPage(matrix: matrix)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('api-matrix-search')),
        '1717',
      );
      await tester.tap(find.byKey(const ValueKey('api-matrix-group')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Riproduzione').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey('api-cell-1717-reproduction_soredia_or_similar'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Indicazione documentata nella strategia riproduttiva.'),
        findsOneWidget,
      );
      expect(find.textContaining('soredia-like'), findsOneWidget);
      expect(
        find.textContaining('non conferma da sola soredi veri o isidi veri'),
        findsOneWidget,
      );
      expect(find.text('Fonte ITALIC'), findsOneWidget);
      expect(find.text('Fonte API'), findsNothing);
      expect(find.text('Salva'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Phone search and cell detail show source without editing reviews',
    (tester) async {
      tester.view.physicalSize = const Size(375, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(home: ItalicApiTraitsPage(matrix: matrix)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('api-matrix-search')),
        '1717',
      );
      await tester.pumpAndSettle();
      expect(find.text('1–1 di 1 taxon'), findsOneWidget);
      final cell = find.byKey(
        const ValueKey('api-cell-1717-growth_form_foliose'),
      );
      await tester.ensureVisible(cell);
      await tester.tap(cell);
      await tester.pumpAndSettle();
      expect(find.text('Valore API: 1 · stato selezionato.'), findsOneWidget);
      expect(
        find.textContaining('https://italic.units.it/api/v2/traits-pa/1717'),
        findsOneWidget,
      );
      expect(find.text('Salva'), findsNothing);
      await tester.tap(find.text('Chiudi'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('api-matrix-search')),
        'nessuna specie',
      );
      await tester.pumpAndSettle();
      expect(find.text('Nessun taxon per questa ricerca.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Group filter exposes reaction conflict and original quote', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: ItalicApiTraitsPage(matrix: matrix)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('api-matrix-search')),
      '1717',
    );
    await tester.tap(find.byKey(const ValueKey('api-matrix-group')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reazione K').last);
    await tester.pumpAndSettle();
    final cell = find.byKey(
      const ValueKey('api-cell-1717-cortex_k_yellow_turning_to_red'),
    );
    await tester.ensureVisible(cell);
    await tester.tap(cell);
    await tester.pumpAndSettle();
    expect(
      find.text('Da confrontare · Reazione K della corteccia'),
      findsOneWidget,
    );
    expect(find.textContaining('upper cortex K+ yellow'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
