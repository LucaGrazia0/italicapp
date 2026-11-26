import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:italicapp/data/identification_repository.dart';
import 'package:italicapp/data/original_key_repository.dart';
import 'package:italicapp/pages/original_key_page.dart';
import 'package:italicapp/widgets/official_key_link.dart';
import 'package:italicapp/data/italic_reference_repository.dart';

Map<String, dynamic> fixture({bool missing = false}) => {
  'id': 1566,
  'status': 'available',
  'title': 'Peltigera · original source title',
  'credits': 'Original authors',
  'introduction': 'Original introduction',
  'sourceUrl':
      'https://italic.units.it/flora/index.php?procedure=ext_key_home&key_id=1566',
  'license': 'CC BY-SA 4.0',
  'accessedOn': '2026-11-26',
  'sha256': List.filled(64, 'a').join(),
  'missingTargets': [if (missing) 9],
  'nodes': [
    {
      'number': 1,
      'choices': [
        {'label': 'Cyanobacterial photobiont', 'target': missing ? 9 : 2},
        {'label': 'Green photobiont', 'name': 'Peltigera green'},
      ],
    },
    if (!missing)
      {
        'number': 2,
        'choices': [
          {
            'label': 'Soredia present',
            'name': 'Peltigera test',
            'description': 'Original terminal description',
          },
          {'label': 'Soredia absent', 'name': 'Unknown species'},
        ],
      },
  ],
};

OriginalKeyArchive archive(Map key) => OriginalKeyArchive.fromMap({
  'schemaVersion': 1,
  'source': 'Published ITALIC/FRIDA original textual keys',
  'keys': [key],
});

final entry = GenusKey(
  genus: 'Peltigera',
  name: 'Peltigera',
  url: Uri.parse(
    'https://italic.units.it/flora/index.php?procedure=ext_key_home&key_id=1566',
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'The bundled catalogue routes to the exact original key, including shared family keys',
    () {
      final data = OriginalKeyArchive.fromMap(
        jsonDecode(File(OriginalKeyArchive.asset).readAsStringSync()) as Map,
      );
      final catalogue =
          (jsonDecode(
                    File(
                      'assets/italic/italic_genus_keys.json',
                    ).readAsStringSync(),
                  )['keys']
                  as List)
              .cast<Map>()
              .map(GenusKey.fromMap)
              .whereType<GenusKey>()
              .toList();
      final ids = catalogue.map(OriginalKeyArchive.keyId).toSet();
      expect({...data.keys.keys, ...data.unavailable}, ids);
      final peltigera = data.forEntry(
        catalogue.firstWhere((k) => k.genus == 'Peltigera'),
      )!;
      expect(
        peltigera.candidates(1),
        contains('Peltigera praetextata (Sommerf.) Zopf'),
      );
      expect(
        peltigera.nodes[1]!.choices[0].label,
        'Main photobiont cyanobacterial. Thallus dark when wet',
      );
      final physcia = data.forEntry(
        catalogue.firstWhere((k) => k.genus == 'Physcia'),
      )!;
      expect(physcia.id, 6405);
      expect(physcia.title, contains('PHYSCIACEAE'));
      expect(
        physcia.candidates(1).any((name) => !name.startsWith('Physcia ')),
        isTrue,
      );
    },
  );

  testWidgets(
    'The original key button opens the bundled Peltigera route inside the app',
    (tester) async {
      await tester.runAsync(() async {
        await OriginalKeyArchive.load();
        await ItalicReferenceRepository().load();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: OfficialKeyLink(entry: entry)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byType(TextButton));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.byType(OriginalKeyPage), findsOneWidget);
      expect(find.text('Bivio 1'), findsOneWidget);
      expect(
        find.text('Main photobiont cyanobacterial. Thallus dark when wet'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('original-choice-0')));
      await tester.pumpAndSettle();
      expect(find.text('Bivio 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'Graph validation rejects cycles, orphan nodes and mismatched missing targets',
    () {
      final cycle = fixture();
      ((cycle['nodes'] as List)[0]['choices'] as List)[0]['target'] = 1;
      expect(() => archive(cycle), throwsFormatException);
      final missing = fixture(missing: true);
      expect(archive(missing).keys[1566]!.unresolved(1), {9});
      missing['missingTargets'] = [];
      expect(() => archive(missing), throwsFormatException);
      final wrong = fixture();
      wrong['sourceUrl'] = 'https://example.com/key';
      expect(() => archive(wrong), throwsFormatException);
    },
  );

  testWidgets(
    'Offline navigation, remaining taxa, terminal and previous couplet',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: OriginalKeyPage(
            entry: entry,
            archive: Future.value(archive(fixture())),
            reference: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bivio 1'), findsOneWidget);
      expect(find.text('3 taxa rimasti · mostra elenco'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('original-choice-0')));
      await tester.pumpAndSettle();
      expect(find.text('Bivio 2'), findsOneWidget);
      expect(find.text('2 taxa rimasti · mostra elenco'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('original-key-candidates')));
      await tester.pumpAndSettle();
      expect(find.text('Peltigera test'), findsOneWidget);
      expect(find.text('Unknown species'), findsOneWidget);
      Navigator.of(tester.element(find.text('Unknown species'))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('original-choice-0')));
      await tester.pumpAndSettle();
      expect(find.text('Peltigera test'), findsOneWidget);
      expect(
        find.text('Esito della chiave originale · da verificare sul campione.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('original-key-back')));
      await tester.pumpAndSettle();
      expect(find.text('Bivio 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'An unavailable key or source continuation is never replaced by another key',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OriginalKeyPage(
            entry: entry,
            archive: Future.value(OriginalKeyArchive({}, {1566})),
            reference: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Questa chiave non è disponibile nella copia offline',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('original-choice-0')), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          home: OriginalKeyPage(
            key: const ValueKey('missing-continuation'),
            entry: entry,
            archive: Future.value(archive(fixture(missing: true))),
            reference: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('original-choice-0')));
      await tester.pumpAndSettle();
      expect(
        find.text('Continuazione 9 non disponibile nella fonte acquisita.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Disconnected source couplets stay in the full text without changing the route',
    (tester) async {
      final raw = fixture(missing: true);
      raw['unreachableCouplets'] = [2];
      (raw['nodes'] as List).add({
        'number': 2,
        'choices': [
          {'label': 'Orphan source condition A', 'name': 'Orphan species A'},
          {'label': 'Orphan source condition B', 'name': 'Orphan species B'},
        ],
      });
      final data = archive(raw);
      expect(
        data.keys[1566]!.candidates(1),
        isNot(contains('Orphan species A')),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: OriginalKeyPage(
            entry: entry,
            archive: Future.value(data),
            reference: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Collegamenti incompleti nella fonte'), findsOneWidget);
      await tester.tap(find.text('Consulta tutti i bivi'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Orphan source condition A'), findsOneWidget);
      expect(
        find.text('Non raggiungibile dai collegamenti pubblicati.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
