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
import 'package:italicapp/services/character_dictionary.dart';
import 'package:italicapp/services/physcia_review_engine.dart';
import 'package:italicapp/services/reviewed_matrix.dart';

void main() {
  final dictionary = CharacterDictionary.fromMap(
    jsonDecode(
      File('assets/italic/character_dictionary_v3.json').readAsStringSync(),
    ),
  );
  late CharacterMatrix matrix;
  MatrixTaxon row(int id) =>
      matrix.taxa.singleWhere((r) => r.taxon.italicId == id);
  DictionaryAnalysis lookup(String id, String text) => dictionary.analyze(
    text,
    dictionary.characters.singleWhere((c) => c.id == id),
  );
  ReviewProposal proposal(int taxonId, String id) => PhysciaPilot.proposal(
    row(taxonId),
    PhysciaPilot.character(id)!,
    dictionary: dictionary,
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
  });

  test(
    'Albinea: multiple upper colours, explicit absences and separate surfaces',
    () {
      expect(
        proposal(1719, 'upper_surface_colour').value,
        'bluish_grey|grey|white',
      );
      expect(proposal(1719, 'upper_surface_pruina').value, 'absent');
      expect(proposal(1719, 'upper_surface_maculation').value, 'absent');
      expect(proposal(1719, 'lower_surface_colour').value, 'brown');
      expect(proposal(1719, 'medulla_colour').value, 'white');
      expect(proposal(1719, 'thallus_type').value, 'foliose');
      expect(proposal(1719, 'lobe_profile').value, 'convex');
      // Numeric width is preserved as evidence; no arbitrary narrow/broad cutoff.
      expect(proposal(1719, 'lobe_width_class').value, 'unknown');
      expect(
        proposal(1719, 'upper_surface_colour').quote,
        contains('(especially at lobe-tips)'),
      );
    },
  );

  test(
    'Aipolia: colour is distinct from macules, pruinose disc and reagents',
    () {
      expect(proposal(1718, 'upper_surface_colour').value, 'whitish_grey');
      expect(proposal(1718, 'upper_surface_maculation').value, 'present');
      expect(proposal(1718, 'upper_surface_pruina').value, 'unknown');
      expect(proposal(1718, 'lower_surface_colour').value, 'lead_grey|white');
      expect(proposal(1718, 'medulla_colour').value, 'white');
      expect(proposal(1718, 'lobe_profile').value, 'convex|flat');
      expect(proposal(1718, 'thallus_attachment').value, 'close');
      expect(proposal(1718, 'lobe_width_class').value, 'narrow');
    },
  );

  test(
    'Adscendens: ranges, strap-shaped ascending lobes and loose attachment',
    () {
      expect(proposal(1717, 'thallus_type').value, 'foliose|subfruticose');
      expect(proposal(1717, 'upper_surface_colour').value, 'grey|white');
      expect(proposal(1717, 'upper_surface_maculation').value, 'present');
      expect(proposal(1717, 'upper_surface_pruina').value, 'unknown');
      expect(proposal(1717, 'lobe_shape').value, 'strap_shaped');
      expect(proposal(1717, 'lobe_posture').value, 'ascending');
      expect(proposal(1717, 'thallus_attachment').value, 'loose');
      expect(proposal(1717, 'thallus_outline').value, 'irregular');
      expect(proposal(1717, 'lower_surface_colour').value, 'white');
    },
  );

  test(
    'Accessory structures, anatomy and chemical reactions cannot supply surface colours',
    () {
      const text =
          'Lobes grey, white-maculate, with brown-tipped cilia and blue-grey soralia. '
          'Lower surface white, with brown rhizines. Upper cortex yellow; medulla white; '
          'lower cortex with rounded cells. Apothecia black, white-pruinose. '
          'Spot tests: upper cortex and medulla K+ yellow. Chemistry: medulla orange.';
      expect(lookup('upper_surface_colour', text).value, 'grey');
      expect(lookup('upper_surface_pruina', text).value, isNull);
      expect(lookup('upper_surface_maculation', text).value, 'present');
      expect(lookup('lower_surface_colour', text).value, 'white');
      expect(lookup('medulla_colour', text).value, 'white');
      expect(lookup('lobe_shape', text).value, isNull);
      expect(lookup('upper_surface_colour', 'Apothecia black.').hits, isEmpty);
      expect(
        lookup(
          'upper_surface_colour',
          'Lobes brown, whitish grey-maculate.',
        ).value,
        'brown',
      );
      expect(lookup('medulla_colour', 'Medulla K+ yellow.').hits, isEmpty);
      expect(
        lookup('medulla_colour', 'Medulla white, K+ yellow.').value,
        'white',
      );
      expect(
        lookup('medulla_colour', 'Spot tests: medulla K+ yellow.').hits,
        isEmpty,
      );
    },
  );

  test(
    'Missing, conditional, negated and contradictory statements remain uncertain',
    () {
      expect(
        lookup('upper_surface_maculation', 'Lobes grey.').status,
        'not_documented',
      );
      expect(
        lookup('upper_surface_colour', 'Lobes sometimes grey or brown.').status,
        'needs_review',
      );
      expect(
        lookup('thallus_type', 'Thallus not foliose, but crustose.').status,
        'needs_review',
      );
      expect(
        lookup('upper_surface_pruina', 'Lobes pruinose and epruinose.').status,
        'needs_review',
      );
      expect(
        lookup('upper_surface_maculation', 'Lobes without maculae.').value,
        'absent',
      );
      expect(
        lookup('upper_surface_pruina', 'Lobes not pruinose.').value,
        'absent',
      );
      expect(lookup('lobe_profile', 'Lobes flat to slightly convex.').values, [
        'convex',
        'flat',
      ]);
    },
  );

  test(
    'All new proposals keep exact source offsets and include all selected states in the quote',
    () {
      for (final source in matrix.taxa.where(
        (r) => PhysciaPilot.inScope(r.taxon),
      )) {
        for (final c in dictionary.characters.where((c) => c.scope != null)) {
          final analysis = dictionary.analyze(source.taxon.description!, c);
          for (final hit in analysis.hits) {
            expect(
              source.taxon.description!.substring(hit.start, hit.end),
              hit.quote,
            );
          }
          final p = PhysciaPilot.proposal(
            source,
            PhysciaPilot.character(c.id)!,
            dictionary: dictionary,
          );
          if (p.isCandidate) {
            for (final value in analysis.values) {
              expect(
                analysis.hits
                    .where((h) => h.state!.value == value)
                    .any((h) => p.quote.contains(h.quote)),
                isTrue,
              );
            }
          }
        }
      }
      const text = '🌿 Lobes 0.5-0.8 mm wide, grey. Upper surface white.';
      final hits = lookup('upper_surface_colour', text).hits;
      expect(
        hits.map((h) => text.substring(h.start, h.end)),
        hits.map((h) => h.quote),
      );
    },
  );

  test(
    'Multiple values persist with history and filter by overlap only after manual approval',
    () async {
      final source = row(1719);
      final c = PhysciaPilot.character('upper_surface_colour')!;
      final p = proposal(1719, c.id);
      final factory = newIdbFactoryMemory();
      final store = CharacterReviewRepository(factory: factory);
      CharacterReview review(String status, [CharacterReview? previous]) =>
          CharacterReview.create(
            taxon: source.taxon,
            characterId: c.id,
            value: p.value,
            status: status,
            reviewer: 'Revisore test',
            quote: p.quote,
            previous: previous,
          );
      final draft = review('draft');
      await store.save(draft, source.taxon);
      final reopened = CharacterReviewRepository(factory: factory);
      var registry = ReviewRegistry(await reopened.all());
      final displayed = reviewedMatrix(matrix, registry);
      final cell = displayed.taxa
          .singleWhere((r) => r.taxon.italicId == 1719)
          .cell(c.id);
      expect(cell.values.toSet(), {'white', 'grey', 'bluish_grey'});
      expect(
        cell.label(displayed.characters.singleWhere((d) => d.id == c.id)),
        contains('Grigio azzurrato'),
      );
      expect(
        PhysciaReviewEngine().evaluate(matrix, registry, {
          c.id: 'grey',
        }).matching,
        isEmpty,
      );
      final approved = review('reviewed', draft);
      await store.save(approved, source.taxon);
      registry = ReviewRegistry(await reopened.all());
      for (final value in ['white', 'grey', 'bluish_grey']) {
        expect(
          PhysciaReviewEngine()
              .evaluate(matrix, registry, {c.id: value})
              .matching
              .single
              .row
              .taxon
              .italicId,
          1719,
        );
      }
      expect(
        PhysciaReviewEngine()
            .evaluate(matrix, registry, {c.id: 'black'})
            .different
            .single
            .row
            .taxon
            .italicId,
        1719,
      );
      expect(registry.history(1719, c.id), hasLength(2));
      expect(c.validValue('grey|unknown'), isFalse);
      expect(c.validValue('grey|grey'), isFalse);
      expect(
        PhysciaPilot.character('rhizines_type')!.validValue('simple|branched'),
        isFalse,
      );
    },
  );

  testWidgets(
    'Phone: multiple colours can be changed and saved with the original quotation',
    (tester) async {
      tester.view.physicalSize = const Size(375, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = _Store();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CharacterReviewPage(
                      row: row(1719),
                      character: PhysciaPilot.character(
                        'upper_surface_colour',
                      )!,
                      registry: ReviewRegistry([]),
                      repository: store,
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
      final grey = find.byKey(const ValueKey('review-option-grey'));
      await tester.scrollUntilVisible(
        grey,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(tester.element(grey), alignment: 0.2);
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(grey).selected, isTrue);
      await tester.tap(grey);
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(grey).selected, isFalse);
      final author = find.byKey(const ValueKey('review-author'));
      await tester.scrollUntilVisible(
        author,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(author, 'Revisore test');
      await tester.tap(find.byKey(const ValueKey('save-character-review')));
      await tester.pumpAndSettle();
      expect(store.saved!.value, 'bluish_grey|white');
      expect(store.saved!.quote, contains('especially at lobe-tips'));
      expect(store.saved!.status, 'draft');
      expect(tester.takeException(), isNull);
    },
  );
}

class _Store extends CharacterReviewRepository {
  CharacterReview? saved;
  @override
  Future<void> save(CharacterReview review, ItalicTaxon taxon) async {
    PhysciaPilot.validate(review, taxon);
    saved = review;
  }
}
