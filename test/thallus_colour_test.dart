import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:italicapp/data/character_matrix_repository.dart';
import 'package:italicapp/data/italic_api_traits_repository.dart';
import 'package:italicapp/data/italic_reference_repository.dart';
import 'package:italicapp/models/character_review.dart';
import 'package:italicapp/pages/general_keys_page.dart';
import 'package:italicapp/services/character_dictionary.dart';
import 'package:italicapp/services/key_prefilter.dart';
import 'package:italicapp/services/reconstructed_key.dart';
import 'package:italicapp/services/thallus_colour.dart';

void main() {
  late CharacterDictionary dictionary;
  late CharacterMatrix base, full;
  late ReconstructedKey key;
  late ApiTraitsMatrix api;
  setUpAll(() {
    Map read(String name) =>
        jsonDecode(File('assets/italic/$name.json').readAsStringSync()) as Map;
    final reference = (read('italic_checklist')['taxa'] as List)
        .cast<Map>()
        .map((r) => ItalicTaxon.fromMap(Map<String, dynamic>.from(r)))
        .toList();
    dictionary = CharacterDictionary.fromMap(read('character_dictionary_v3'));
    base = CharacterMatrix.fromMap(read('character_matrix_v2'), reference);
    key = ReconstructedKey.fromMap(
      read('general_reconstructed_key_v1'),
      reference,
    );
    api = ApiTraitsMatrix.fromMap(read('api_traits_matrix_v2'), reference);
    full = ThallusColour.prepare(base, dictionary);
  });

  MatrixTaxon sample(String description) => MatrixTaxon(
    ItalicTaxon(
      italicId: 1,
      scientificName: 'Absconditella annexa (Arnold) Vězda',
      description: description,
    ),
    {},
  );
  MatrixTaxon prepared(String text) => ThallusColour.prepare(
    CharacterMatrix(base.characters, [sample(text)]),
    dictionary,
  ).taxa.single;

  test(
    'Only upper thallus colours filter; lower surface, pruina, macules, apothecia and chemistry do not leak in',
    () {
      final row = prepared(
        'Thallus foliose, grey, white-maculate, with yellow soralia and black cilia. Lower surface brown. Apothecia orange, with a white-pruinose disc. Medulla white. Spot tests: thallus K+ yellow.',
      );
      expect(row.cell(ThallusColour.characterId).values, ['grey']);
      expect(ThallusColour.matches(row, 'light'), true);
      for (final c in ['green', 'yellow', 'orange', 'brown', 'black']) {
        expect(ThallusColour.matches(row, c), false);
      }
    },
  );

  test(
    'Conditions, missing descriptions, and colours found only in notes remain unknown',
    () {
      for (final text in [
        '',
        'Thallus grey when dry, green when wet.',
        'Thallus crustose. Note: Other species have a yellow thallus.',
        'Apothecia orange. Medulla white. Lower surface black.',
      ]) {
        final row = prepared(text);
        expect(ThallusColour.matches(row, 'yellow'), isNull, reason: text);
      }
    },
  );

  test(
    'Documented multiple colours and compound shades preserve all compatible groups',
    () {
      final row = prepared('Thallus grey to brown.');
      expect(ThallusColour.matches(row, 'light'), true);
      expect(ThallusColour.matches(row, 'brown'), true);
      expect(ThallusColour.matches(row, 'yellow'), false);
      final compound = prepared('Thallus greenish-grey.');
      expect(ThallusColour.matches(compound, 'light'), true);
      expect(ThallusColour.matches(compound, 'green'), true);
    },
  );

  test(
    'Manual revisions take precedence; a draft, unknown or stale review suspends extraction',
    () {
      final row = sample('Thallus grey to brown.');
      for (final status in ['reviewed', 'draft', 'clarify']) {
        final record = CharacterReview.create(
          taxon: row.taxon,
          characterId: ThallusColour.characterId,
          value: 'brown',
          status: status,
          reviewer: 'Test',
          quote: 'Thallus grey to brown.',
        );
        final result = ThallusColour.prepare(
          CharacterMatrix(base.characters, [row]),
          dictionary,
          registry: ReviewRegistry([record]),
        ).taxa.single;
        expect(
          ThallusColour.matches(result, 'light'),
          status == 'reviewed' ? false : null,
        );
      }
      final old = CharacterReview.create(
        taxon: sample('Thallus grey.').taxon,
        characterId: ThallusColour.characterId,
        value: 'grey',
        status: 'reviewed',
        reviewer: 'Test',
        quote: 'Thallus grey.',
      );
      final stale = ThallusColour.prepare(
        CharacterMatrix(base.characters, [row]),
        dictionary,
        registry: ReviewRegistry([old]),
      ).taxa.single;
      expect(ThallusColour.matches(stale, 'light'), isNull);
    },
  );

  test(
    'Colour prunes the actual key, keeps missing rows, combines with binary filters and survives path serialization',
    () {
      final grey = sample('Thallus grey.');
      final yellowTaxon = ItalicTaxon(
        scientificName: key.taxa[3323]!.scientificName,
        italicId: 3323,
        description: 'Thallus yellow.',
      );
      final matrix = ThallusColour.prepare(
        CharacterMatrix(base.characters, [grey, MatrixTaxon(yellowTaxon, {})]),
        dictionary,
      );
      final comparison = KeyPrefilter(key, matrix, {ThallusColour.id: 'light'});
      expect(comparison.eligible, contains(1));
      expect(comparison.uncertain, isNot(contains(1)));
      expect(comparison.excluded, contains(3323));
      expect(comparison.eligible, contains(2872));
      expect(comparison.uncertain, contains(2872));
      final filtered = key.filtered(comparison.eligible, comparison.filters);
      expect(KeyPrefilter.restore(filtered.normalize({})), {
        ThallusColour.id: 'light',
      });
      expect(KeyPrefilter.normalize({ThallusColour.id: 'nonsense'}), isEmpty);
      final combined = KeyPrefilter(key, matrix, {
        ThallusColour.id: 'light',
        'binary:growth_form_foliose': '1',
      }, apiMatrix: api);
      expect(combined.eligible, isNot(contains(3323)));
      expect(combined.eligible.every(comparison.eligible.contains), true);
    },
  );

  test(
    'Real data colour coverage is source-bound and does not alter base assets',
    () {
      final coverage = ThallusColour.coverage(full);
      expect(coverage, greaterThan(0));
      expect(coverage, lessThan(full.taxa.length));
      expect(
        base.characters.any((c) => c.id == ThallusColour.characterId),
        false,
      );
      final counts = {
        for (final c in ThallusColour.question.choices)
          c.id: full.taxa
              .where((r) => ThallusColour.matches(r, c.id) == true)
              .length,
      };
      debugPrint(
        'COLOUR_COVERAGE_JSON=${jsonEncode({'taxa': full.taxa.length, 'comparable': coverage, 'unknown': full.taxa.length - coverage, 'groups': counts})}',
      );
    },
  );

  testWidgets(
    'Phone: colour choices are visible in the initial thallus group and affect the key count',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: GeneralKeysPage(definition: key, matrix: full, apiMatrix: api),
        ),
      );
      await tester.pumpAndSettle();
      final group = find.descendant(
        of: find.byKey(const ValueKey('binary-group-Tallo')),
        matching: find.text('Tallo'),
      );
      await tester.scrollUntilVisible(
        group,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(group);
      await tester.pump();
      await tester.tap(group);
      await tester.pumpAndSettle();
      final orange = find.byKey(
        const ValueKey('prefilter-thallusColour-orange'),
      );
      await tester.scrollUntilVisible(
        orange,
        130,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(orange);
      await tester.pump();
      await tester.tap(orange);
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(orange).selected, true);
      final count = find.byKey(const ValueKey('prefilter-count'));
      await tester.scrollUntilVisible(
        count,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      final expected = KeyPrefilter(key, full, {
        ThallusColour.id: 'orange',
      }, apiMatrix: api);
      expect(
        tester.widget<Text>(count).data,
        startsWith('${expected.coveredLocal} taxa'),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
