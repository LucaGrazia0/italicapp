import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:italicapp/data/character_matrix_repository.dart';
import 'package:italicapp/data/character_review_repository.dart';
import 'package:italicapp/data/italic_reference_repository.dart';
import 'package:italicapp/models/character_review.dart';
import 'package:italicapp/pages/character_matrix_page.dart';
import 'package:italicapp/pages/physcia_review_page.dart';
import 'package:italicapp/pages/physcia_key_page.dart';
import 'package:italicapp/services/physcia_review_engine.dart';
import 'package:italicapp/services/character_dictionary.dart';
import 'package:italicapp/services/reviewed_matrix.dart';

void main() {
  final dictionary = CharacterDictionary.fromMap(
    jsonDecode(
      File('assets/italic/character_dictionary_v3.json').readAsStringSync(),
    ),
  );
  late CharacterMatrix base;
  late MatrixTaxon row;
  setUpAll(() {
    final source =
        jsonDecode(
              File('assets/italic/italic_checklist.json').readAsStringSync(),
            )
            as Map;
    final taxa = (source['taxa'] as List)
        .cast<Map>()
        .map((t) => ItalicTaxon.fromMap(Map<String, dynamic>.from(t)))
        .toList();
    base = CharacterMatrix.fromMap(
      jsonDecode(
        File('assets/italic/character_matrix_v2.json').readAsStringSync(),
      ),
      taxa,
    );
    row = base.taxa.firstWhere((r) => r.taxon.italicId == 1717);
  });

  CharacterReview edit({String status = 'draft', CharacterReview? previous}) =>
      CharacterReview.create(
        taxon: row.taxon,
        characterId: 'soredia',
        value: 'present',
        status: status,
        reviewer: 'Revisore test',
        quote: 'terminal, hood-shaped soralia',
        previous: previous,
      );

  CharacterReview absence({
    String status = 'reviewed',
    CharacterReview? previous,
  }) => CharacterReview.create(
    taxon: row.taxon,
    characterId: 'soredia',
    value: 'absent',
    status: status,
    reviewer: 'Revisore test',
    quote: '',
    previous: previous,
  );

  CharacterReview soralia(String id) => CharacterReview.create(
    taxon: row.taxon,
    characterId: id,
    value: id == 'soralia_shape' ? 'hood' : 'terminal',
    status: 'reviewed',
    reviewer: 'Revisore test',
    quote: 'terminal, hood-shaped soralia',
  );

  test(
    'Absence makes shape and position inapplicable without deleting history',
    () async {
      final factory = newIdbFactoryMemory();
      final store = CharacterReviewRepository(factory: factory);
      final oldShape = soralia('soralia_shape');
      final oldPosition = soralia('soralia_position');
      await store.save(oldShape, row.taxon);
      await store.save(oldPosition, row.taxon);
      final missing = absence();
      await store.save(missing, row.taxon);
      var registry = ReviewRegistry(
        await CharacterReviewRepository(factory: factory).all(),
      );
      final result = reviewedMatrix(
        base,
        registry,
      ).taxa.firstWhere((r) => r.taxon.italicId == 1717);
      for (final id in ['soralia_shape', 'soralia_position']) {
        expect(result.cell(id).isNotApplicable, isTrue);
        expect(result.cell(id).label(base.characters.first), 'Non applicabile');
        expect(result.cell(id).applicabilityReview!.id, missing.id);
        expect(registry.history(1717, id), hasLength(1));
      }
      final conflicting = CharacterReview.create(
        taxon: row.taxon,
        characterId: 'soralia_shape',
        value: 'hood',
        status: 'reviewed',
        reviewer: 'Revisore test',
        quote: oldShape.quote,
        previous: oldShape,
      );
      await expectLater(
        store.save(conflicting, row.taxon),
        throwsA(isA<ReviewNotApplicable>()),
      );
      expect(await store.all(), hasLength(3));
      await store.save(edit(status: 'reviewed', previous: missing), row.taxon);
      registry = ReviewRegistry(await store.all());
      final restored = reviewedMatrix(
        base,
        registry,
      ).taxa.firstWhere((r) => r.taxon.italicId == 1717);
      expect(restored.cell('soralia_shape').values, ['hood']);
      expect(restored.cell('soralia_position').values, ['terminal']);
    },
  );

  test(
    'Unknown, variable and changed absence sources do not imply inapplicability',
    () {
      for (final value in ['unknown', 'variable']) {
        final record = CharacterReview.create(
          taxon: row.taxon,
          characterId: 'soredia',
          value: value,
          status: 'draft',
          reviewer: 'Revisore test',
          quote: value == 'unknown' ? '' : 'hood-shaped soralia',
          notes: 'Da verificare',
        );
        final result = reviewedMatrix(base, ReviewRegistry([record]));
        expect(
          result.taxa
              .firstWhere((r) => r.taxon.italicId == 1717)
              .cell('soralia_shape')
              .isNotApplicable,
          isFalse,
        );
      }
      final changed = ItalicTaxon(
        scientificName: row.taxon.scientificName,
        italicId: 1717,
        description: 'Updated source',
      );
      expect(
        PhysciaPilot.sorediaAbsence(ReviewRegistry([absence()]), changed),
        isNull,
      );
    },
  );

  test('Key respects both sample and taxon applicability and draft status', () {
    final shape = soralia('soralia_shape');
    for (final status in ['reviewed', 'draft']) {
      final registry = ReviewRegistry([shape, absence(status: status)]);
      final result = PhysciaReviewEngine().evaluate(base, registry, {
        'soralia_shape': 'hood',
      });
      final candidate =
          (status == 'reviewed' ? result.different : result.uncertain)
              .singleWhere((r) => r.row.taxon.italicId == 1717);
      expect(candidate.criteria.single.notApplicable, isTrue);
      expect(
        candidate.criteria.single.matches,
        status == 'reviewed' ? false : null,
      );
    }
    final result = PhysciaReviewEngine().evaluate(
      base,
      ReviewRegistry([shape, absence()]),
      {
        'soredia': 'absent',
        'soralia_shape': 'hood',
        'soralia_position': 'terminal',
      },
    );
    expect(result.matching.single.row.taxon.italicId, 1717);
    expect(result.matching.single.criteria, hasLength(1));
  });

  testWidgets('Review hub and editor explain inapplicable shape and position', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = _Store()
      ..records.addAll([soralia('soralia_shape'), absence(status: 'draft')]);
    await tester.pumpWidget(
      MaterialApp(
        home: PhysciaReviewPage(
          dictionary: dictionary,
          matrix: CharacterMatrix(base.characters, [row]),
          reviewRepository: store,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Forma dei sorali: Non applicabile'), findsOneWidget);
    expect(find.text('Posizione dei sorali: Non applicabile'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('review-cell-1717-soralia_shape')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review-not-applicable')), findsOneWidget);
    expect(find.byKey(const ValueKey('save-character-review')), findsNothing);
    expect(store.records, hasLength(2));
  });

  testWidgets('Sample absence disables and clears both soralia inputs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: PhysciaKeyPage(
          matrix: CharacterMatrix(base.characters, [row]),
          registry: ReviewRegistry([]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('physcia-confirm-genus')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('physcia-select-soralia_shape-unknown')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('A cappuccio').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('physcia-select-soredia-unknown')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assente').last);
    await tester.pumpAndSettle();
    for (final id in ['soralia_shape', 'soralia_position']) {
      expect(
        find.byKey(ValueKey('physcia-not-applicable-$id')),
        findsOneWidget,
      );
    }
    await tester.tap(
      find.byKey(const ValueKey('physcia-select-soredia-absent')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Presente').last);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('physcia-select-soralia_shape-unknown')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('physcia-select-soralia_position-unknown')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  test(
    'Saved edits survive repository reopening and appear in the matrix',
    () async {
      final factory = newIdbFactoryMemory();
      final saved = edit();
      await CharacterReviewRepository(factory: factory).save(saved, row.taxon);
      final records = await CharacterReviewRepository(factory: factory).all();
      final result = reviewedMatrix(base, ReviewRegistry(records));
      final cell = result.taxa
          .firstWhere((r) => r.taxon.italicId == 1717)
          .cell('soredia');
      expect(cell.values, ['present']);
      expect(cell.manualReview!.id, saved.id);
      expect(cell.reviewLabel, 'Bozza');
      expect(base.characters.length, 25);
      expect(result.characters.length, 48);
      expect(row.cell('soredia').manualReview, isNull);
      expect(
        PhysciaReviewEngine().evaluate(base, ReviewRegistry(records), {
          'soredia': 'present',
        }).matching,
        isEmpty,
      );
    },
  );

  test(
    'Latest draft and changed source never fall back to an older approval',
    () {
      final approved = edit(status: 'reviewed');
      final draft = edit(previous: approved);
      final registry = ReviewRegistry([draft, approved]);
      final result = reviewedMatrix(base, registry);
      expect(
        result.taxa
            .firstWhere((r) => r.taxon.italicId == 1717)
            .cell('soredia')
            .manualReview!
            .id,
        draft.id,
      );
      final changed = CharacterMatrix(base.characters, [
        MatrixTaxon(
          ItalicTaxon(
            scientificName: row.taxon.scientificName,
            italicId: 1717,
            description: 'Updated source',
          ),
          row.cells,
        ),
      ]);
      final stale = reviewedMatrix(
        changed,
        registry,
      ).taxa.single.cell('soredia');
      expect(stale.stale, isTrue);
      expect(
        stale.label(result.characters.firstWhere((c) => c.id == 'soredia')),
        'Fonte da aggiornare',
      );
    },
  );

  test('Manual absence needs neither quotation nor motivation', () async {
    final record = CharacterReview.create(
      taxon: row.taxon,
      characterId: 'soredia',
      value: 'absent',
      status: 'reviewed',
      reviewer: 'Revisore test',
      quote: '',
    );
    final factory = newIdbFactoryMemory();
    await CharacterReviewRepository(factory: factory).save(record, row.taxon);
    final registry = ReviewRegistry(
      await CharacterReviewRepository(factory: factory).all(),
    );
    final cell = reviewedMatrix(
      base,
      registry,
    ).taxa.firstWhere((r) => r.taxon.italicId == 1717).cell('soredia');
    expect(cell.values, ['absent']);
    expect(cell.manualReview!.notes, isEmpty);
    expect(cell.evidence, isEmpty);
    expect(
      PhysciaReviewEngine()
          .evaluate(base, registry, {'soredia': 'absent'})
          .matching
          .single
          .row
          .taxon
          .italicId,
      1717,
    );
    final undocumentedPresence = CharacterReview.create(
      taxon: row.taxon,
      characterId: 'soredia',
      value: 'present',
      status: 'draft',
      reviewer: 'Revisore test',
      quote: '',
    );
    expect(
      () => PhysciaPilot.validate(undocumentedPresence, row.taxon),
      throwsFormatException,
    );
  });

  test(
    'Apothecia support both types, manual absence and traceable proposals',
    () async {
      final character = PhysciaPilot.character('apothecia_type')!;
      expect(
        character.values.keys,
        containsAll(['lecideine', 'lecanorine', 'absent', 'unknown']),
      );
      final proposal = PhysciaPilot.proposal(
        row,
        character,
        dictionary: dictionary,
      );
      expect(proposal.value, 'lecanorine');
      expect(proposal.status, 'candidate');
      expect(proposal.quote, contains('very rare'));
      expect(row.taxon.description, contains(proposal.quote));
      final factory = newIdbFactoryMemory();
      final repository = CharacterReviewRepository(factory: factory);
      CharacterReview? previous;
      for (final value in ['lecanorine', 'lecideine', 'absent']) {
        final record = CharacterReview.create(
          taxon: row.taxon,
          characterId: character.id,
          value: value,
          status: 'reviewed',
          reviewer: 'Revisore test',
          quote: value == 'absent' ? '' : proposal.quote,
          previous: previous,
        );
        await repository.save(record, row.taxon);
        final registry = ReviewRegistry(await repository.all());
        final result = reviewedMatrix(base, registry);
        expect(
          result.taxa
              .firstWhere((r) => r.taxon.italicId == 1717)
              .cell(character.id)
              .values,
          [value],
        );
        expect(
          PhysciaReviewEngine()
              .evaluate(base, registry, {character.id: value})
              .matching
              .single
              .row
              .taxon
              .italicId,
          1717,
        );
        previous = record;
      }
      expect((await repository.all()).length, 3);
    },
  );

  testWidgets(
    'Editing a matrix cell refreshes it immediately and on reopening',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = _Store();
      final small = CharacterMatrix(base.characters, [row]);
      Widget app() => MaterialApp(
        home: CharacterMatrixPage(
          dictionary: dictionary,
          matrix: small,
          reviewRepository: store,
        ),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('matrix-group')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Morfologia').last);
      await tester.pumpAndSettle();
      final target = find.byKey(const ValueKey('matrix-cell-1717-soredia'));
      await tester.tap(target);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Revisiona questa cella'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('review-value-present')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Assente').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('review-author')),
        'Revisore test',
      );
      await tester.enterText(find.byKey(const ValueKey('review-quote')), '');
      await tester.tap(find.byKey(const ValueKey('save-character-review')));
      await tester.pumpAndSettle();
      expect(store.records.single.value, 'absent');
      expect(
        find.descendant(
          of: target,
          matching: find.text('Assente · Bozza\nRevisore test'),
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(find.text('Autore: Revisore test · versione 1'), findsOneWidget);
      expect(
        find.text('Assenza indicata manualmente dall’autore, senza citazione.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Unavailable reviews are disclosed rather than silently omitted',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CharacterMatrixPage(
            dictionary: dictionary,
            matrix: base,
            reviewRepository: _Unavailable(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Revisioni locali non disponibili'),
        findsOneWidget,
      );
      expect(find.text('1–20 di 3588 taxa'), findsOneWidget);
    },
  );
}

class _Store extends CharacterReviewRepository {
  final records = <CharacterReview>[];
  @override
  Future<List<CharacterReview>> all() async => List.of(records);
  @override
  Future<void> save(CharacterReview review, ItalicTaxon taxon) async {
    PhysciaPilot.validate(review, taxon);
    records.add(review);
  }
}

class _Unavailable extends CharacterReviewRepository {
  @override
  Future<List<CharacterReview>> all() async => throw StateError('Unavailable');
}
