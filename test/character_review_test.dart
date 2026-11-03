import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:italicapp/data/character_matrix_repository.dart';
import 'package:italicapp/data/character_review_repository.dart';
import 'package:italicapp/data/italic_reference_repository.dart';
import 'package:italicapp/models/character_review.dart';
import 'package:italicapp/services/physcia_review_engine.dart';
import 'package:italicapp/services/character_dictionary.dart';
import 'package:italicapp/pages/character_review_page.dart';
import 'package:italicapp/pages/physcia_review_page.dart';
import 'package:italicapp/pages/physcia_key_page.dart';
import 'package:italicapp/theme/app_theme.dart';

void main() {
  final dictionary = CharacterDictionary.fromMap(
    jsonDecode(
      File('assets/italic/character_dictionary_v3.json').readAsStringSync(),
    ),
  );
  late CharacterMatrix matrix;
  late MatrixTaxon adscendens, tenella;
  final shape = PhysciaPilot.character('soralia_shape')!;
  setUpAll(() {
    final source =
        jsonDecode(
              File('assets/italic/italic_checklist.json').readAsStringSync(),
            )
            as Map;
    final taxa = (source['taxa'] as List)
        .cast<Map>()
        .map((r) => ItalicTaxon.fromMap(Map<String, dynamic>.from(r)))
        .toList();
    matrix = CharacterMatrix.fromMap(
      jsonDecode(
        File('assets/italic/character_matrix_v2.json').readAsStringSync(),
      ),
      taxa,
    );
    adscendens = matrix.taxa.singleWhere((r) => r.taxon.italicId == 1717);
    tenella = matrix.taxa.singleWhere((r) => r.taxon.italicId == 1735);
  });

  CharacterReview record({
    MatrixTaxon? row,
    String status = 'reviewed',
    String? value,
    String? quote,
    String notes = '',
    CharacterReview? previous,
  }) {
    final target = row ?? adscendens;
    return CharacterReview.create(
      taxon: target.taxon,
      characterId: shape.id,
      value: value ?? (target == tenella ? 'labriform' : 'hood'),
      status: status,
      reviewer: 'Revisore test',
      quote:
          quote ??
          (target == tenella ? 'labriform soralia' : 'hood-shaped soralia'),
      notes: notes,
      previous: previous,
    );
  }

  test('Physcia proposals are traceable and are never reviews', () {
    final rows = matrix.taxa
        .where((r) => PhysciaPilot.inScope(r.taxon))
        .toList();
    expect(rows.length, 22);
    expect(PhysciaPilot.characters.length, 27);
    for (final row in rows) {
      for (final c in PhysciaPilot.characters) {
        final p = PhysciaPilot.proposal(row, c, dictionary: dictionary);
        expect(c.validValue(p.value), isTrue);
        if (p.quote.isNotEmpty) {
          expect(row.taxon.description, contains(p.quote));
        }
      }
    }
    expect(
      PhysciaPilot.proposal(adscendens, shape, dictionary: dictionary).value,
      'hood',
    );
    final soredia = PhysciaPilot.proposal(
      adscendens,
      PhysciaPilot.character('soredia')!,
      dictionary: dictionary,
    );
    expect(soredia.value, 'present');
    expect(soredia.quote, contains('soralia'));
    expect(soredia.explanation, contains('sorali'));
    expect(adscendens.cell('soredia').review, 'needs_review');
    expect(
      PhysciaPilot.proposal(tenella, shape, dictionary: dictionary).value,
      'labriform',
    );
    final result = PhysciaReviewEngine().evaluate(matrix, ReviewRegistry([]), {
      'soralia_shape': 'hood',
    });
    expect(result.matching, isEmpty);
    expect(result.uncertain.length, 22);
    expect(result.different, isEmpty);
  });

  test('Manual review retains all unreviewed taxa as uncertain', () {
    final registry = ReviewRegistry([record(), record(row: tenella)]);
    final result = PhysciaReviewEngine().evaluate(matrix, registry, {
      'soralia_shape': 'hood',
    });
    expect(result.matching.single.row.taxon.italicId, 1717);
    expect(result.different.single.row.taxon.italicId, 1735);
    expect(result.uncertain.length, 20);
    expect(
      result.matching.single.criteria.single.review!.reviewer,
      'Revisore test',
    );
  });

  test('Draft, clarification, variable and changed source never filter', () {
    for (final r in [
      record(status: 'draft'),
      record(status: 'clarify'),
      record(value: 'variable', notes: 'Varia con l’età'),
    ]) {
      expect(PhysciaPilot.usable(r, adscendens.taxon, shape), isFalse);
    }
    final r = record();
    final changed = ItalicTaxon(
      scientificName: adscendens.taxon.scientificName,
      italicId: 1717,
      description: '${adscendens.taxon.description} Revised.',
    );
    expect(PhysciaPilot.usable(r, changed, shape), isFalse);
    final draft = record(status: 'draft', previous: r);
    final registry = ReviewRegistry([r, draft]);
    expect(registry.latest(1717, shape.id), same(draft));
    expect(
      PhysciaReviewEngine().evaluate(matrix, registry, {
        'soralia_shape': 'hood',
      }).matching,
      isEmpty,
    );
  });

  test(
    'Invalid quotations, reviewers and variable-without-note are rejected',
    () {
      expect(
        () =>
            PhysciaPilot.validate(record(quote: 'invented'), adscendens.taxon),
        throwsFormatException,
      );
      expect(
        () =>
            PhysciaPilot.validate(record(value: 'variable'), adscendens.taxon),
        throwsFormatException,
      );
      final blankAuthor = CharacterReview.create(
        taxon: adscendens.taxon,
        characterId: shape.id,
        value: 'hood',
        status: 'reviewed',
        reviewer: ' ',
        quote: 'hood-shaped soralia',
      );
      expect(
        () => PhysciaPilot.validate(blankAuthor, adscendens.taxon),
        throwsFormatException,
      );
      final unknown = record(value: 'unknown', quote: '');
      PhysciaPilot.validate(unknown, adscendens.taxon);
      expect(PhysciaPilot.usable(unknown, adscendens.taxon, shape), isFalse);
    },
  );

  test(
    'Persistence appends history and rejects stale concurrent edits',
    () async {
      final factory = newIdbFactoryMemory();
      final repository = CharacterReviewRepository(factory: factory);
      final first = record(status: 'draft');
      await repository.save(first, adscendens.taxon);
      final second = record(previous: first);
      await repository.save(second, adscendens.taxon);
      final reopened = CharacterReviewRepository(factory: factory);
      final registry = ReviewRegistry(await reopened.all());
      expect(registry.records.length, 2);
      expect(registry.history(1717, shape.id).map((r) => r.version), [2, 1]);
      expect(
        registry.latest(1717, shape.id)!.createdAt.toUtc(),
        second.createdAt,
      );
      expect(
        registry.latest(1717, shape.id)!.sourceDescription,
        adscendens.taxon.description,
      );
      await expectLater(
        reopened.save(record(previous: first), adscendens.taxon),
        throwsA(isA<ReviewConflict>()),
      );
      expect((await reopened.all()).length, 2);
      final roundTrip = CharacterReview.fromMap(second.toMap());
      expect(roundTrip.toMap(), second.toMap());
    },
  );

  Future<void> enterAuthor(WidgetTester tester) async {
    final finder = find.byKey(const ValueKey('review-author'));
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(finder, 'Revisore locale');
  }

  testWidgets(
    'Phone: revision form requires author and saves only a draft by default',
    (tester) async {
      tester.view.physicalSize = const Size(375, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _RecordingRepository();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CharacterReviewPage(
                      dictionary: dictionary,
                      row: adscendens,
                      character: shape,
                      registry: ReviewRegistry([]),
                      repository: repository,
                    ),
                  ),
                ),
                child: const Text('Apri revisione'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Apri revisione'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-character-review')));
      await tester.pumpAndSettle();
      expect(await repository.all(), isEmpty);
      await enterAuthor(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-character-review')));
      await tester.pumpAndSettle();
      final saved = (await repository.all()).single;
      expect(saved.status, 'draft');
      expect(saved.reviewer, 'Revisore locale');
      expect(saved.value, 'hood');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'A reviewed save is explicit and storage failure preserves typed content',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _FailingRepository();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: CharacterReviewPage(
            dictionary: dictionary,
            row: adscendens,
            character: shape,
            registry: ReviewRegistry([]),
            repository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('review-status-draft')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Revisionato manualmente').last);
      await tester.pumpAndSettle();
      await enterAuthor(tester);
      await tester.tap(find.byKey(const ValueKey('save-character-review')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Salvataggio non riuscito.'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('review-author')))
            .controller!
            .text,
        'Revisore locale',
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('review-quote')))
            .controller!
            .text,
        contains('hood-shaped soralia'),
      );
    },
  );

  testWidgets('Review hub searches Physcia and opens source-backed cells', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PhysciaReviewPage(
          dictionary: dictionary,
          matrix: matrix,
          reviewRepository: _RecordingRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('22 taxa × 27 caratteri'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byKey(const ValueKey('physcia-open-matrix')),
      ),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('physcia-review-search')),
      '1717',
    );
    await tester.pumpAndSettle();
    expect(find.text(adscendens.taxon.scientificName), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('review-cell-1717-soralia_shape')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Revisiona · Forma dei sorali'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('review-source-description')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.byKey(const ValueKey('review-source-description')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Experimental key gates genus and shows incomplete coverage', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PhysciaKeyPage(
          matrix: matrix,
          registry: ReviewRegistry([record()]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('physcia-key-count')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('physcia-confirm-genus')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('physcia-select-soralia_shape-unknown')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('A cappuccio').last);
    await tester.pumpAndSettle();
    expect(
      find.text(
        '1 corrispondenti ai dati revisionati · 21 non valutabili · 0 con differenze',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

class _FailingRepository extends CharacterReviewRepository {
  @override
  Future<void> save(CharacterReview review, ItalicTaxon taxon) async =>
      throw StateError('Simulated storage failure');
}

class _RecordingRepository extends CharacterReviewRepository {
  final records = <CharacterReview>[];
  @override
  Future<List<CharacterReview>> all() async => List.of(records);
  @override
  Future<void> save(CharacterReview review, ItalicTaxon taxon) async {
    PhysciaPilot.validate(review, taxon);
    records.add(review);
  }
}
