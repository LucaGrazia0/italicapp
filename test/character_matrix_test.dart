import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:italicapp/data/character_review_repository.dart';
import 'package:italicapp/data/character_matrix_repository.dart';
import 'package:italicapp/data/italic_reference_repository.dart';
import 'package:italicapp/pages/character_matrix_page.dart';
import 'package:italicapp/theme/app_theme.dart';

void main() {
  late CharacterMatrix matrix;
  late List<ItalicTaxon> taxa;
  late Map source;
  setUpAll(() {
    taxa =
        (jsonDecode(
                  File(
                    'assets/italic/italic_checklist.json',
                  ).readAsStringSync(),
                )['taxa']
                as List)
            .cast<Map>()
            .map((m) => ItalicTaxon.fromMap(Map<String, dynamic>.from(m)))
            .toList();
    source =
        jsonDecode(
              File('assets/italic/character_matrix_v2.json').readAsStringSync(),
            )
            as Map;
    matrix = CharacterMatrix.fromMap(source, taxa);
  });

  test('Coverage, provenance and missing states remain distinct', () {
    expect(matrix.taxa.length, 3588);
    expect(matrix.characters.length, 25);
    expect(matrix.staleCells, 0);
    expect(matrix.availableCells, 24135);
    final caperata = matrix.taxa.singleWhere((r) => r.taxon.italicId == 978);
    expect(caperata.cell('pilot_medulla_K').values, ['dirty_yellow']);
    expect(caperata.cell('pilot_medulla_K').review, 'needs_expert_review');
    expect(caperata.cell('growthForm').isStructured, isTrue);
    final noData = matrix.taxa.firstWhere((r) => r.cell('soredia').isUnknown);
    expect(noData.cell('soredia').values, isEmpty);
    expect(
      noData
          .cell('soredia')
          .label(matrix.characters.singleWhere((c) => c.id == 'soredia')),
      'Non codificato',
    );
  });

  test('A changed description suspends the extracted values', () {
    final changed = taxa
        .map(
          (t) => t.italicId == 978
              ? ItalicTaxon(
                  scientificName: t.scientificName,
                  italicId: t.italicId,
                  description: 'Revised description',
                  ecologyCodes: t.ecologyCodes,
                )
              : t,
        )
        .toList();
    final result = CharacterMatrix.fromMap(source, changed);
    final caperata = result.taxa.singleWhere((r) => r.taxon.italicId == 978);
    expect(caperata.cell('pilot_medulla_K').stale, isTrue);
    expect(caperata.cell('pilot_medulla_K').isUnknown, isTrue);
    expect(caperata.cell('pilot_medulla_K').values, isEmpty);
    expect(caperata.cell('growthForm').isStructured, isTrue);
    expect(result.staleCells, greaterThan(0));
  });

  test('Changed identity and incomplete coverage reject the matrix', () {
    final renamed = taxa
        .map(
          (t) => t.italicId == 978
              ? const ItalicTaxon(
                  scientificName: 'Renamed species',
                  italicId: 978,
                )
              : t,
        )
        .toList();
    expect(
      () => CharacterMatrix.fromMap(source, renamed),
      throwsFormatException,
    );
    expect(
      () => CharacterMatrix.fromMap(source, taxa.skip(1).toList()),
      throwsFormatException,
    );
  });

  testWidgets(
    'Search, pagination and missing evidence are available on a phone',
    (tester) async {
      tester.view.physicalSize = const Size(375, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: CharacterMatrixPage(
            matrix: matrix,
            reviewRepository: CharacterReviewRepository(
              factory: newIdbFactoryMemory(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1–20 di 3588 taxa'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('matrix-next')));
      await tester.pumpAndSettle();
      expect(find.text('21–40 di 3588 taxa'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('matrix-search')),
        '978',
      );
      await tester.pumpAndSettle();
      expect(find.text('1–1 di 1 taxon'), findsOneWidget);
      final target = find.byKey(
        const ValueKey('matrix-cell-978-pilot_medulla_K'),
      );
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(
        find.text('Codifica manuale del pilota · da revisionare'),
        findsOneWidget,
      );
      expect(find.text('“medulla K+ dirty yellow”'), findsOneWidget);
      await tester.tap(find.text('Chiudi'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('matrix-clear-search')));
      await tester.pumpAndSettle();
      expect(find.text('1–20 di 3588 taxa'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('matrix-search')),
        'taxon inesistente',
      );
      await tester.pumpAndSettle();
      expect(find.text('Nessun taxon per questa ricerca.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Category selection and unknown cell explain missing data', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: CharacterMatrixPage(
          matrix: matrix,
          reviewRepository: CharacterReviewRepository(
            factory: newIdbFactoryMemory(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('matrix-search')), '978');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('matrix-group')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Morfologia').last);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('matrix-cell-978-growthForm')),
      findsNothing,
    );
    final unknown = matrix.taxa.firstWhere((r) => r.cell('isidia').isUnknown);
    await tester.enterText(
      find.byKey(const ValueKey('matrix-search')),
      unknown.taxon.italicId.toString(),
    );
    await tester.pumpAndSettle();
    final target = find.byKey(
      ValueKey('matrix-cell-${unknown.taxon.italicId}-isidia'),
    );
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Nessuna informazione codificata. Non equivale all’assenza del carattere.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Load errors can be retried', (tester) async {
    final repository = _RetryRepository(matrix);
    await tester.pumpWidget(
      MaterialApp(
        home: CharacterMatrixPage(
          repository: repository,
          reviewRepository: CharacterReviewRepository(
            factory: newIdbFactoryMemory(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Impossibile caricare la matrice locale.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();
    expect(find.text('1–20 di 3588 taxa'), findsOneWidget);
  });
}

class _RetryRepository extends CharacterMatrixRepository {
  _RetryRepository(this.matrix);
  final CharacterMatrix matrix;
  bool first = true;
  @override
  Future<CharacterMatrix> load({int? revision}) async {
    if (first) {
      first = false;
      throw StateError('Unavailable');
    }
    return matrix;
  }
}
