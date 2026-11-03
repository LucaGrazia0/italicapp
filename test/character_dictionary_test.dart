import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:italicapp/pages/character_dictionary_page.dart';
import 'package:italicapp/services/character_dictionary.dart';
import 'package:italicapp/data/character_matrix_repository.dart';
import 'package:italicapp/data/character_review_repository.dart';
import 'package:italicapp/data/italic_reference_repository.dart';
import 'package:italicapp/models/character_review.dart';
import 'package:italicapp/services/physcia_review_engine.dart';
import 'package:italicapp/pages/character_review_page.dart';

void main() {
  final dictionary = CharacterDictionary.fromMap(
    jsonDecode(
      File('assets/italic/character_dictionary_v3.json').readAsStringSync(),
    ),
  );
  DictionaryCharacter entry(String id) =>
      dictionary.characters.singleWhere((c) => c.id == id);
  List<DictionaryHit> lookup(String id, String text) =>
      dictionary.find(text, entry(id));

  test('Dictionary covers presence and types of all requested structures', () {
    expect(dictionary.characters, hasLength(27));
    for (final id in [
      'soralia_shape',
      'soralia_position',
      'soredia_texture',
      'isidia_shape',
      'cilia_type',
      'rhizines_type',
      'apothecia_type',
      'apothecia_shape',
    ]) {
      expect(entry(id).states, isNotEmpty);
      expect(entry(id).context, isNotEmpty);
    }
    expect(entry('rhizines_type').contains('dichotomously'), isTrue);
    expect(entry('rhizines_type').contains('semplici'), isTrue);
  });

  test('Aliases, negation and missing information remain distinct', () {
    for (final text in ['Cilia black.', 'Cilium black.', 'Ciglia presenti.']) {
      expect(lookup('cilia', text).single.status, 'present');
    }
    expect(lookup('cilia', 'Cilia absent.').single.status, 'absent');
    expect(lookup('cilia', 'Without cilia.').single.status, 'absent');
    expect(lookup('cilia', 'Thallus crustose.'), isEmpty);
    expect(
      lookup('cilia', 'With or without cilia.').single.status,
      'uncertain',
    );
    expect(
      lookup('isidia', 'Thallus with isidia-like structures.').single.status,
      'uncertain',
    );
  });

  test('Soralia imply soredia but absence does not imply absent soredia', () {
    expect(
      lookup('soredia', 'Lobes with hood-shaped soralia.').single.status,
      'present',
    );
    expect(lookup('soredia', 'Soralia absent.').single.status, 'uncertain');
    expect(
      lookup('soredia', 'The name refers to soralia.').single.status,
      'uncertain',
    );
  });

  test('Shape descriptors bind to the appropriate structure', () {
    const text =
        'Rhizines simple. Paraphyses branched, with capitate apical cells. Soralia labriform. Apothecia lecanorine. Lower cortex with rounded cells.';
    expect(lookup('rhizines_type', text).map((h) => h.state!.value), [
      'simple',
    ]);
    expect(lookup('soralia_shape', text).map((h) => h.state!.value), [
      'labriform',
    ]);
    expect(lookup('cilia_type', text), isEmpty);
    expect(lookup('apothecia_shape', text), isEmpty);
    expect(lookup('apothecia_type', text).single.state!.value, 'lecanorine');
    const mixed =
        'Lobes with marginal cilia and terminal, hood-shaped soralia.';
    expect(lookup('soralia_position', mixed).map((h) => h.state!.value), [
      'terminal',
    ]);
  });

  test('Specific compound terms and multiple states retain their context', () {
    expect(
      lookup(
        'rhizines_type',
        'Rhizines dichotomously branched.',
      ).map((h) => h.state!.value),
      ['dichotomous'],
    );
    final mixed = lookup('rhizines_type', 'Rhizines simple to squarrose.');
    expect(mixed.map((h) => h.state!.value).toSet(), {'simple', 'squarrose'});
    expect(mixed.every((h) => h.status == 'uncertain'), isTrue);
    expect(
      lookup('cilia_type', 'Cilia sometimes forked.').single.status,
      'uncertain',
    );
  });

  test('Source quotations keep exact offsets and decimal measurements', () {
    const text =
        '🌱 Lobes 0.5-1.5 mm wide, with simple rhizines. Soralia labriform.';
    final hit = lookup('rhizines_type', text).single;
    expect(hit.quote, contains('0.5-1.5'));
    expect(text.substring(hit.start, hit.end), hit.quote);
    final taxa =
        (jsonDecode(
                  File(
                    'assets/italic/italic_checklist.json',
                  ).readAsStringSync(),
                )['taxa']
                as List)
            .cast<Map>();
    final description =
        taxa.singleWhere((t) => t['italicId'] == 1717)['description'] as String;
    expect(lookup('soralia_shape', description).single.state!.value, 'hood');
    expect(
      lookup('soralia_position', description).single.state!.value,
      'terminal',
    );
    final aipolia =
        taxa.singleWhere((t) => t['italicId'] == 1718)['description'] as String;
    expect(lookup('rhizines_type', aipolia).single.state!.value, 'simple');
    expect(lookup('apothecia_shape', aipolia), isEmpty);
  });

  testWidgets(
    'Search filters dictionary and finds types in pasted descriptions',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(home: CharacterDictionaryPage(dictionary: dictionary)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('dictionary-query')),
        'rizine',
      );
      await tester.enterText(
        find.byKey(const ValueKey('dictionary-source')),
        'Lower surface with simple rhizines.',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('dictionary-entry-cilia_type')),
        findsNothing,
      );
      expect(find.textContaining('Semplici · Tipo candidato'), findsOneWidget);
      expect(find.textContaining('Termine trovato: simple'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Evidence picker returns exact quotation and type for a draft', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    DictionaryHit? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                selected = await Navigator.push<DictionaryHit>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CharacterDictionaryPage(
                      dictionary: dictionary,
                      sourceText: 'Lower surface with simple rhizines.',
                      initialConcept: 'rhizines',
                      pickEvidence: true,
                    ),
                  ),
                );
              },
              child: const Text('Cerca'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Cerca'));
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('dictionary-entry-rhizines_type'));
    final button = find.descendant(
      of: card,
      matching: find.text('Usa citazione come bozza'),
    );
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(selected!.state!.value, 'simple');
    expect(selected!.quote, 'Lower surface with simple rhizines.');
    expect(selected!.character.parent, 'rhizines');
  });

  testWidgets('Picked type and quotation persist as a draft review note', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final taxa =
        (jsonDecode(
                  File(
                    'assets/italic/italic_checklist.json',
                  ).readAsStringSync(),
                )['taxa']
                as List)
            .cast<Map>();
    final taxon = ItalicTaxon.fromMap(
      Map<String, dynamic>.from(taxa.singleWhere((t) => t['italicId'] == 1718)),
    );
    final store = _ReviewStore();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CharacterReviewPage(
                    dictionary: dictionary,
                    row: MatrixTaxon(taxon, {}),
                    character: PhysciaPilot.character('rhizines')!,
                    registry: ReviewRegistry([]),
                    repository: store,
                  ),
                ),
              ),
              child: const Text('Revisiona'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Revisiona'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('review-open-dictionary')));
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('dictionary-entry-rhizines_type'));
    final button = find.descendant(
      of: card,
      matching: find.text('Usa citazione come bozza'),
    );
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review-value-present')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('review-author')),
      'Revisore test',
    );
    await tester.tap(find.byKey(const ValueKey('save-character-review')));
    await tester.pumpAndSettle();
    expect(store.saved!.quote, contains('simple rhizines'));
    expect(store.saved!.notes, contains('Semplici'));
    expect(store.saved!.status, 'draft');
    expect(store.saved!.value, 'present');
  });
}

class _ReviewStore extends CharacterReviewRepository {
  CharacterReview? saved;
  @override
  Future<void> save(CharacterReview review, ItalicTaxon taxon) async {
    PhysciaPilot.validate(review, taxon);
    saved = review;
  }
}
