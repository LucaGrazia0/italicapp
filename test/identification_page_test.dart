import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:italicapp/app_store.dart';
import 'package:italicapp/data/identification_repository.dart';
import 'package:italicapp/data/italic_reference_repository.dart';
import 'package:italicapp/data/observation_repository.dart';
import 'package:italicapp/models/identification_path.dart';
import 'package:italicapp/models/observation.dart';
import 'package:italicapp/pages/identification_page.dart';
import 'package:italicapp/services/identification_engine.dart';
import 'package:italicapp/theme/app_theme.dart';

void main() {
  final key = IdentificationKey.fromMap(
    jsonDecode(File('assets/italic/flavoparmelia_key.json').readAsStringSync()),
  );
  final taxa =
      (jsonDecode(
                File('assets/italic/italic_checklist.json').readAsStringSync(),
              )['taxa']
              as List)
          .where((t) => [978, 979].contains(t['italicId']))
          .map((t) => ItalicTaxon.fromMap(Map<String, dynamic>.from(t)))
          .toList();

  testWidgets(
    'Conferma genere, bivi, salvataggio e ripresa senza assegnare una specie',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = _RecordingStore();
      final observation = _observation();
      final repo = _Repository(taxa, key);
      Widget page(Key identity) => MaterialApp(
        theme: AppTheme.light,
        home: DichotomousKeyPage(
          key: identity,
          definition: key,
          repository: repo,
          observation: observation,
          store: store,
        ),
      );
      await tester.pumpWidget(page(const ValueKey('first')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('answer-a')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('confirm-genus')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('answer-a')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Reazione K della medulla'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('answer-a')));
      await tester.pumpAndSettle();
      expect(find.text('Candidati da verificare'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('save-identification-path')),
      );
      await tester.tap(find.byKey(const ValueKey('save-identification-path')));
      await tester.pumpAndSettle();
      expect(observation.identificationPath!.answers, {
        'soredia': KeyAnswer.a,
        'medulla_k': KeyAnswer.a,
      });
      expect(store.saved!.rank, IdentificationRank.undetermined);
      expect(store.saved!.taxonName, isNull);
      await tester.pumpWidget(page(const ValueKey('resumed')));
      await tester.pumpAndSettle();
      expect(find.text('Candidati da verificare'), findsOneWidget);
      expect(find.byKey(const ValueKey('answer-a')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Un salvataggio fallito non modifica il percorso precedente', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final observation = _observation();
    final previous = IdentificationPath(
      keyId: 'previous-key',
      answers: {'previous': KeyAnswer.b},
      savedAt: DateTime.utc(2026, 10, 19),
    );
    observation.identificationPath = previous;
    final store = _RecordingStore()..fail = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: DichotomousKeyPage(
          definition: key,
          repository: _Repository(taxa, key),
          observation: observation,
          store: store,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-genus')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('answer-a')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('save-identification-path')),
    );
    await tester.tap(find.byKey(const ValueKey('save-identification-path')));
    await tester.pumpAndSettle();
    expect(observation.identificationPath, same(previous));
    expect(find.textContaining('Salvataggio non riuscito'), findsOneWidget);
    expect(find.byKey(const ValueKey('answer-a')), findsOneWidget);
  });

  testWidgets('Macrocaratteri: si può tornare indietro e cambiare ramo', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: DichotomousKeyPage(
          definition: IdentificationKey.macro,
          repository: _Repository(taxa, key),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('answer-b')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('answer-a')));
    await tester.pumpAndSettle();
    expect(find.text('Candidati da verificare'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Modifica').first,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Modifica').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('answer-a')), findsOneWidget);
    expect(
      find.text('La forma principale del tallo è crostosa?'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Telefono: alternative lunghe e risposte discordanti restano leggibili',
    (tester) async {
      tester.view.physicalSize = const Size(375, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: DichotomousKeyPage(
            definition: key,
            repository: _Repository(taxa, key),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-genus')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('answer-a')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('answer-b')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('answer-b')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('key-candidate-count')),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('0 candidati coerenti'), findsOneWidget);
      expect(
        find.text('Risposte da rivedere o dati insufficienti'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Annulla ripristina un ramo intero e lo stato salvato', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final observation = _observation()
      ..identificationPath = IdentificationPath(
        keyId: key.id,
        answers: {'soredia': KeyAnswer.a, 'medulla_k': KeyAnswer.a},
        savedAt: DateTime.utc(2026, 10, 20),
      );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: DichotomousKeyPage(
          definition: key,
          repository: _Repository(taxa, key),
          observation: observation,
          store: _RecordingStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Risposte salvate nell’osservazione.'), findsOneWidget);
    await tester.tap(find.text('Modifica').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Bivio 1 di 2'), findsOneWidget);
    expect(find.textContaining('sarà rimosso al salvataggio'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('undo-key-change')));
    await tester.pumpAndSettle();
    expect(find.text('Percorso completato · 2 risposte'), findsOneWidget);
    expect(find.text('Risposte salvate nell’osservazione.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('save-identification-path')),
          )
          .onPressed,
      isNull,
    );
    expect(find.text('Modifica'), findsNWidgets(2));
    expect(observation.identificationPath!.answers.length, 2);
  });

  testWidgets(
    'Ricomincia è reversibile e rimuove il salvataggio solo su richiesta',
    (tester) async {
      tester.view.physicalSize = const Size(900, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final previous = IdentificationPath(
        keyId: key.id,
        answers: {'soredia': KeyAnswer.a, 'medulla_k': KeyAnswer.a},
        savedAt: DateTime.utc(2026, 10, 20),
      );
      final observation = _observation()..identificationPath = previous;
      final store = _RecordingStore()..fail = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: DichotomousKeyPage(
            definition: key,
            repository: _Repository(taxa, key),
            observation: observation,
            store: store,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('restart-key')));
      await tester.tap(find.byKey(const ValueKey('restart-key')));
      await tester.pumpAndSettle();
      expect(observation.identificationPath, same(previous));
      await tester.tap(find.byKey(const ValueKey('save-identification-path')));
      await tester.pumpAndSettle();
      expect(observation.identificationPath, same(previous));
      expect(find.textContaining('Salvataggio non riuscito'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('undo-key-change')));
      await tester.pumpAndSettle();
      expect(find.text('Risposte salvate nell’osservazione.'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('restart-key')));
      await tester.tap(find.byKey(const ValueKey('restart-key')));
      await tester.pumpAndSettle();
      store.fail = false;
      await tester.tap(find.byKey(const ValueKey('save-identification-path')));
      await tester.pumpAndSettle();
      expect(observation.identificationPath, isNull);
      expect(store.saved!.identificationPath, isNull);
      expect(store.saved!.latitude, observation.latitude);
      expect(store.saved!.rank, IdentificationRank.undetermined);
    },
  );

  testWidgets('I taxa esclusi mostrano risposte e citazioni discordanti', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: DichotomousKeyPage(
          definition: key,
          repository: _Repository(taxa, key),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-genus')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('answer-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('answer-b')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confronta i taxa esclusi (2)'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Confronto dei caratteri').first);
    await tester.tap(find.text('Confronto dei caratteri').first);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Aspetto dei soredi · Coerente'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Reazione K della medulla · Discordante'),
      findsOneWidget,
    );
    expect(find.textContaining('medulla K+ dirty yellow'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Menu pulito: i vecchi percorsi restano riprendibili e aggiornabili',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final observation = _observation()
        ..identificationPath = IdentificationPath(
          keyId: key.id,
          answers: {key.questions.first.id: KeyAnswer.a},
          savedAt: DateTime.utc(2026, 11, 2),
        );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: DeterminationStartPage(
            repository: _Repository(taxa, key),
            observation: observation,
            store: _RecordingStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final id in [
        'open-macro-key',
        'open-structured-key',
        'open-flavoparmelia-key',
      ]) {
        expect(find.byKey(ValueKey(id)), findsNothing);
      }
      expect(find.byKey(const ValueKey('open-general-keys')), findsOneWidget);
      expect(find.byKey(const ValueKey('resume-key')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('resume-key')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('answer-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-identification-path')));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('2 risposte registrate'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('La ricerca considera il genere e si può azzerare', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: OfficialKeysPage(
          entries: [
            GenusKey(
              genus: 'Caloplaca',
              name: 'Chiave A',
              url: Uri.parse(
                'https://italic.units.it/flora/index.php?procedure=ext_key_home&key_id=1',
              ),
            ),
            GenusKey(
              genus: 'Caloplaca',
              name: 'Chiave B',
              url: Uri.parse(
                'https://italic.units.it/flora/index.php?procedure=ext_key_home&key_id=2',
              ),
            ),
            GenusKey(
              genus: 'Parmelia',
              name: 'Chiave C',
              url: Uri.parse(
                'https://italic.units.it/flora/index.php?procedure=ext_key_home&key_id=3',
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('genus-key-search')),
      '  CALOPLACA ',
    );
    await tester.pumpAndSettle();
    expect(find.text('2 chiavi disponibili'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('genus-key-search')),
      'inesistente',
    );
    await tester.pumpAndSettle();
    expect(find.text('Nessuna chiave per questa ricerca.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('clear-genus-search')));
    await tester.pumpAndSettle();
    expect(find.text('3 chiavi disponibili'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('genus-key-search')))
          .controller!
          .text,
      isEmpty,
    );
  });
}

Observation _observation() => Observation(
  id: 'test',
  createdAt: DateTime.utc(2026, 10, 20),
  latitude: 45,
  longitude: 10,
  horizontalAccuracy: 5,
);

class _Repository extends IdentificationRepository {
  _Repository(this._taxa, IdentificationKey definition) {
    pilot = definition;
  }
  final List<ItalicTaxon> _taxa;
  @override
  List<ItalicTaxon> get taxa => _taxa;
  @override
  Future<void> load() async {}
}

class _RecordingStore extends AppStore {
  _RecordingStore()
    : super(ObservationRepository(factory: newIdbFactoryMemory()));
  Observation? saved;
  bool fail = false;
  @override
  Future<void> save(Observation observation) async {
    if (fail) throw StateError('Simulated storage failure');
    saved = observation;
  }
}
