import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:italicapp/data/character_matrix_repository.dart';
import 'package:italicapp/data/character_review_repository.dart';
import 'package:italicapp/data/italic_reference_repository.dart';
import 'package:italicapp/models/character_review.dart';
import 'package:italicapp/pages/physcia_dictionary_audit_page.dart';
import 'package:italicapp/services/character_dictionary.dart';
import 'package:italicapp/services/physcia_dictionary_audit.dart';
import 'package:italicapp/services/physcia_review_engine.dart';
import 'package:italicapp/services/reviewed_matrix.dart';

void main() {
  final dictionary = CharacterDictionary.fromMap(
    jsonDecode(
      File('assets/italic/character_dictionary_v3.json').readAsStringSync(),
    ),
  );
  late CharacterMatrix matrix;
  late MatrixTaxon adscendens;
  DictionaryAnalysis lookup(String id, String text) => dictionary.analyze(
    text,
    dictionary.characters.singleWhere((c) => c.id == id),
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
    adscendens = matrix.taxa.singleWhere((r) => r.taxon.italicId == 1717);
  });
  CharacterReview record(
    String id,
    String value,
    String quote, {
    String notes = '',
  }) => CharacterReview.create(
    taxon: adscendens.taxon,
    characterId: id,
    value: value,
    quote: quote,
    notes: notes,
    reviewer: 'Revisore test',
    status: 'reviewed',
  );

  test(
    'Soralia have their own presence; absent soralia never prove absent soredia',
    () {
      expect(lookup('soralia', adscendens.taxon.description!).value, 'present');
      expect(lookup('soralia', 'Soralia absent.').value, 'absent');
      expect(lookup('soredia', 'Soralia absent.').value, isNull);
      expect(
        lookup(
          'soralia',
          'Thallus with diffuse soredia, without soralia.',
        ).value,
        'absent',
      );
      expect(lookup('soralia', 'Soredia diffuse.').status, 'not_documented');
      expect(
        lookup('isidia', 'Thallus with isidia-like pustules.').status,
        'needs_review',
      );
    },
  );

  test(
    'Apothecial frequency, insertion, disc pruina and margin remain separate',
    () {
      final text = adscendens.taxon.description!;
      expect(lookup('apothecia_type', text).value, 'lecanorine');
      expect(lookup('apothecia_insertion', text).value, 'short_stipitate');
      expect(lookup('apothecia_disc_pruina', text).status, 'needs_review');
      expect(lookup('upper_surface_pruina', text).status, 'not_documented');
      expect(
        lookup('apothecia_type', text).hits.single.quote,
        contains('very rare'),
      );
      expect(
        lookup(
          'apothecia_type',
          'Apothecia very rare, lecanorine or lecideine.',
        ).status,
        'needs_review',
      );
      expect(
        lookup('apothecia_type', 'Apothecia rare, rarely lecanorine.').status,
        'needs_review',
      );
      expect(
        lookup(
          'apothecia_disc_pruina',
          'Apothecia lecanorine, with an epruinose disc and a pruinose thalline margin.',
        ).value,
        'absent',
      );
      expect(lookup('apothecia_disc_pruina', 'Lobes pruinose.').hits, isEmpty);
      expect(lookup('apothecia_insertion', 'Pycnidia immersed.').hits, isEmpty);
    },
  );

  test(
    'Audit surfaces organ mixups and changed values without editing reviews',
    () {
      final records = [
        record(
          'upper_surface_colour',
          'white|whitish_grey',
          'whitish to very pale grey',
        ),
        record(
          'upper_surface_pruina',
          'other',
          'sometimes pruinose disc',
          notes: 'Apoteci',
        ),
        record(
          'apothecia_shape',
          'other',
          'short-stipitate',
          notes: 'Brevemente peduncolati',
        ),
        record('isidia', 'absent', ''),
        record('soredia', 'present', 'hood-shaped soralia'),
      ];
      final before = jsonEncode(records.map((r) => r.toMap()).toList());
      final registry = ReviewRegistry(records);
      final cells = PhysciaDictionaryAudit().analyze(
        CharacterMatrix(matrix.characters, [adscendens]),
        dictionary,
        registry,
      );
      expect(cells, hasLength(27));
      expect(
        cells
            .where((c) => c.status == PhysciaAuditStatus.compare)
            .map((c) => c.character.id)
            .toSet(),
        {'upper_surface_colour', 'upper_surface_pruina', 'apothecia_shape'},
      );
      expect(
        cells
            .singleWhere((c) => c.character.id == 'upper_surface_pruina')
            .relatedCharacter!
            .id,
        'apothecia_disc_pruina',
      );
      expect(
        cells
            .singleWhere((c) => c.character.id == 'apothecia_shape')
            .relatedCharacter!
            .id,
        'apothecia_insertion',
      );
      expect(
        cells.singleWhere((c) => c.character.id == 'isidia').status,
        PhysciaAuditStatus.manual,
      );
      expect(
        cells.singleWhere((c) => c.character.id == 'isidia_shape').status,
        PhysciaAuditStatus.notApplicable,
      );
      expect(
        cells.singleWhere((c) => c.character.id == 'soredia').status,
        PhysciaAuditStatus.consistent,
      );
      expect(
        cells.singleWhere((c) => c.character.id == 'soralia').status,
        PhysciaAuditStatus.available,
      );
      expect(
        jsonEncode(registry.records.map((r) => r.toMap()).toList()),
        before,
      );
    },
  );

  test(
    'Saved unknowns remain saved, source changes are flagged, and only Physcia are audited',
    () {
      final unknown = record('thallus_type', 'unknown', '');
      final registry = ReviewRegistry([unknown]);
      final cells = PhysciaDictionaryAudit().analyze(
        matrix,
        dictionary,
        registry,
      );
      expect(cells, hasLength(22 * 27));
      final cell = cells.singleWhere(
        (c) => c.row.taxon.italicId == 1717 && c.character.id == 'thallus_type',
      );
      expect(cell.status, PhysciaAuditStatus.available);
      expect(cell.record!.value, 'unknown');
      final altered = MatrixTaxon(
        ItalicTaxon(
          scientificName: adscendens.taxon.scientificName,
          italicId: 1717,
          description: '${adscendens.taxon.description} Source changed.',
        ),
        {},
      );
      final stale = PhysciaDictionaryAudit().analyze(
        CharacterMatrix(matrix.characters, [altered]),
        dictionary,
        registry,
      );
      expect(
        stale.singleWhere((c) => c.character.id == 'thallus_type').status,
        PhysciaAuditStatus.stale,
      );
    },
  );

  test(
    'Absent soralia disable shape and position while keeping soredia applicable',
    () async {
      final taxon = ItalicTaxon(
        scientificName: 'Physcia test',
        italicId: 990001,
        description: 'Thallus with diffuse soredia, without soralia.',
      );
      final row = MatrixTaxon(taxon, {});
      final base = CharacterMatrix([], [row]);
      final factory = newIdbFactoryMemory();
      final store = CharacterReviewRepository(factory: factory);
      final absence = CharacterReview.create(
        taxon: taxon,
        characterId: 'soralia',
        value: 'absent',
        status: 'reviewed',
        quote: 'without soralia',
        reviewer: 'Revisore test',
      );
      await store.save(absence, taxon);
      final registry = ReviewRegistry(await store.all());
      final display = reviewedMatrix(base, registry).taxa.single;
      for (final id in ['soralia_shape', 'soralia_position']) {
        expect(display.cell(id).isNotApplicable, isTrue);
        final forbidden = CharacterReview.create(
          taxon: taxon,
          characterId: id,
          value: 'unknown',
          status: 'draft',
          quote: '',
          reviewer: 'Revisore test',
        );
        await expectLater(
          store.save(forbidden, taxon),
          throwsA(isA<ReviewNotApplicable>()),
        );
      }
      expect(display.cell('soredia').isNotApplicable, isFalse);
      expect(
        PhysciaPilot.absentSampleParent('soralia_shape', {'soralia': 'absent'}),
        'soralia',
      );
      expect(
        PhysciaPilot.absentSampleParent('soredia', {'soralia': 'absent'}),
        isNull,
      );
      expect(
        PhysciaReviewEngine()
            .evaluate(base, registry, {
              'soralia': 'absent',
              'soralia_shape': 'hood',
            })
            .matching
            .single
            .criteria,
        hasLength(1),
      );
      expect(await store.all(), hasLength(1));
    },
  );

  testWidgets(
    'Audit filters disagreements and opens the correct new review without saving',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = _Store()
        ..records.add(
          record(
            'apothecia_shape',
            'other',
            'short-stipitate',
            notes: 'Peduncolo',
          ),
        );
      await tester.pumpWidget(
        MaterialApp(
          home: PhysciaDictionaryAuditPage(
            matrix: CharacterMatrix(matrix.characters, [adscendens]),
            dictionary: dictionary,
            registry: ReviewRegistry(store.records),
            repository: store,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('27 celle analizzate'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('physcia-audit-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Da confrontare (1)').last);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('physcia-audit-1717-apothecia_shape')),
        findsOneWidget,
      );
      await tester.tap(find.text('Apri Apoteci · inserzione'));
      await tester.pumpAndSettle();
      expect(find.text('Revisiona · Apoteci · inserzione'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('review-value-short_stipitate')),
        findsOneWidget,
      );
      expect(store.records, hasLength(1));
      expect(tester.takeException(), isNull);
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
