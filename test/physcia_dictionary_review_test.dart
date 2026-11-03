import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:italicapp/data/character_matrix_repository.dart';
import 'package:italicapp/data/character_review_repository.dart';
import 'package:italicapp/data/italic_reference_repository.dart';
import 'package:italicapp/models/character_review.dart';
import 'package:italicapp/pages/character_review_page.dart';
import 'package:italicapp/pages/physcia_review_page.dart';
import 'package:italicapp/services/character_dictionary.dart';
import 'package:italicapp/services/physcia_review_engine.dart';
import 'package:italicapp/services/reviewed_matrix.dart';

void main() {
  late CharacterMatrix matrix;
  late MatrixTaxon aipolia;
  final dictionary = CharacterDictionary.fromMap(
    jsonDecode(
      File('assets/italic/character_dictionary_v3.json').readAsStringSync(),
    ),
  );
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
    aipolia = matrix.taxa.singleWhere((r) => r.taxon.italicId == 1718);
  });

  test(
    'Review uses all dictionary groups and the same conservative audit decisions',
    () {
      expect(
        PhysciaPilot.characters.map((c) => c.id).toSet(),
        dictionary.characters.map((c) => c.id).toSet(),
      );
      for (final c in dictionary.characters) {
        expect(
          PhysciaPilot.character(c.id)!.values.keys,
          containsAll(c.states.map((s) => s.value)),
        );
      }
      final counts = <String, int>{};
      for (final row in matrix.taxa.where(
        (r) => PhysciaPilot.inScope(r.taxon),
      )) {
        for (final c in PhysciaPilot.characters.take(12)) {
          final p = PhysciaPilot.proposal(row, c, dictionary: dictionary);
          counts.update(p.status, (n) => n + 1, ifAbsent: () => 1);
          if (p.quote.isNotEmpty) {
            expect(row.taxon.description, contains(p.quote));
          }
          if (!p.isCandidate) expect(p.value, 'unknown');
        }
      }
      expect(counts, {
        'candidate': 68,
        'needs_review': 30,
        'not_documented': 166,
      });
      expect(
        PhysciaPilot.proposal(
          aipolia,
          PhysciaPilot.character('rhizines_type')!,
          dictionary: dictionary,
        ).value,
        'simple',
      );
      expect(
        PhysciaPilot.proposal(
          aipolia,
          PhysciaPilot.character('apothecia_type')!,
          dictionary: dictionary,
        ).value,
        'lecanorine',
      );
      expect(
        PhysciaPilot.proposal(
          aipolia,
          PhysciaPilot.character('apothecia_shape')!,
          dictionary: dictionary,
        ).value,
        'unknown',
      );
    },
  );

  test(
    'A new type persists, appears in the matrix, and filters only after manual review',
    () async {
      final factory = newIdbFactoryMemory();
      final repository = CharacterReviewRepository(factory: factory);
      final c = PhysciaPilot.character('rhizines_type')!;
      final proposal = PhysciaPilot.proposal(
        aipolia,
        c,
        dictionary: dictionary,
      );
      final draft = CharacterReview.create(
        taxon: aipolia.taxon,
        characterId: c.id,
        value: proposal.value,
        quote: proposal.quote,
        reviewer: 'Revisore test',
        status: 'draft',
      );
      await repository.save(draft, aipolia.taxon);
      final reopened = CharacterReviewRepository(factory: factory);
      var registry = ReviewRegistry(await reopened.all());
      final displayed = reviewedMatrix(matrix, registry);
      final cell = displayed.taxa
          .singleWhere((r) => r.taxon.italicId == 1718)
          .cell(c.id);
      expect(cell.values, ['simple']);
      expect(cell.manualReview!.id, draft.id);
      expect(
        PhysciaReviewEngine().evaluate(matrix, registry, {
          c.id: 'simple',
        }).matching,
        isEmpty,
      );
      final approved = CharacterReview.create(
        taxon: aipolia.taxon,
        characterId: c.id,
        value: proposal.value,
        quote: proposal.quote,
        reviewer: 'Revisore test',
        status: 'reviewed',
        previous: draft,
      );
      await reopened.save(approved, aipolia.taxon);
      registry = ReviewRegistry(await reopened.all());
      expect(registry.history(1718, c.id).map((r) => r.version), [2, 1]);
      expect(
        PhysciaReviewEngine()
            .evaluate(matrix, registry, {c.id: 'simple'})
            .matching
            .single
            .row
            .taxon
            .italicId,
        1718,
      );
    },
  );

  test(
    'Every absent structure disables its new dependent fields transactionally',
    () async {
      for (final dep in PhysciaPilot.dependencies.entries) {
        final factory = newIdbFactoryMemory();
        final repository = CharacterReviewRepository(factory: factory);
        final absence = CharacterReview.create(
          taxon: aipolia.taxon,
          characterId: dep.value,
          value: 'absent',
          quote: '',
          reviewer: 'Revisore test',
          status: 'draft',
        );
        await repository.save(absence, aipolia.taxon);
        var registry = ReviewRegistry(await repository.all());
        final cell = reviewedMatrix(
          matrix,
          registry,
        ).taxa.singleWhere((r) => r.taxon.italicId == 1718).cell(dep.key);
        expect(cell.isNotApplicable, isTrue, reason: dep.key);
        final forbidden = CharacterReview.create(
          taxon: aipolia.taxon,
          characterId: dep.key,
          value: 'unknown',
          quote: '',
          reviewer: 'Revisore test',
          status: 'draft',
        );
        await expectLater(
          repository.save(forbidden, aipolia.taxon),
          throwsA(isA<ReviewNotApplicable>()),
        );
        expect(await repository.all(), hasLength(1));
        final uncertain = CharacterReview.create(
          taxon: aipolia.taxon,
          characterId: dep.value,
          value: 'unknown',
          quote: '',
          reviewer: 'Revisore test',
          status: 'draft',
          previous: absence,
        );
        await repository.save(uncertain, aipolia.taxon);
        registry = ReviewRegistry(await repository.all());
        expect(
          PhysciaPilot.absenceFor(registry, aipolia.taxon, dep.key),
          isNull,
        );
      }
    },
  );

  testWidgets(
    'Hub and editor retain a saved unknown instead of replacing it with a candidate',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final saved = CharacterReview.create(
        taxon: aipolia.taxon,
        characterId: 'rhizines_type',
        value: 'unknown',
        quote: '',
        reviewer: 'Autore originale',
        notes: 'Da verificare al microscopio',
        status: 'draft',
      );
      final repository = _Store()..records.add(saved);
      await tester.pumpWidget(
        MaterialApp(
          home: PhysciaReviewPage(
            matrix: CharacterMatrix(matrix.characters, [aipolia]),
            dictionary: dictionary,
            reviewRepository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Tipo di rizine: Non documentato / incerto · Bozza'),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('review-cell-1718-rhizines_type')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('review-value-unknown')),
        findsOneWidget,
      );
      expect(find.text('Proposta del dizionario · Semplici'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('review-use-dictionary-proposal')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('review-value-simple')), findsOneWidget);
      expect(find.byKey(const ValueKey('review-status-draft')), findsOneWidget);
      expect(repository.records.single.id, saved.id);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('review-author')))
            .controller!
            .text,
        'Autore originale',
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('review-notes')))
            .controller!
            .text,
        saved.notes,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('A new type is prefilled with its source and saves as a draft', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _Store();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CharacterReviewPage(
                    row: aipolia,
                    character: PhysciaPilot.character('rhizines_type')!,
                    registry: ReviewRegistry([]),
                    repository: repository,
                    dictionary: dictionary,
                  ),
                ),
              ),
              child: const Text('Apri'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Apri'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review-value-simple')), findsOneWidget);
    expect(repository.records, isEmpty);
    await tester.enterText(
      find.byKey(const ValueKey('review-author')),
      'Revisore test',
    );
    await tester.tap(find.byKey(const ValueKey('save-character-review')));
    await tester.pumpAndSettle();
    final record = repository.records.single;
    expect(record.characterId, 'rhizines_type');
    expect(record.value, 'simple');
    expect(record.quote, contains('simple rhizines'));
    expect(record.status, 'draft');
    expect(tester.takeException(), isNull);
  });
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
