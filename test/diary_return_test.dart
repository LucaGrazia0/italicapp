import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:italicapp/data/italic_reference_repository.dart';
import 'package:italicapp/models/identification_path.dart';
import 'package:italicapp/models/observation.dart';
import 'package:italicapp/pages/observation_page.dart';
import 'package:italicapp/widgets/candidate_selection.dart';
import 'plots_test.dart' as fixtures;

void main() {
  testWidgets(
    'After choosing a species the return button skips the keys and keeps the saved diary record',
    (tester) async {
      final store = (await tester.runAsync(fixtures.plotStore))!;
      final o = Observation(
        id: 'return',
        createdAt: DateTime.now(),
        notes: 'Original notes',
        plotId: 'plot-ref',
        latitude: 45,
        longitude: 11,
      );
      await tester.runAsync(() => store.save(o));
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          home: Scaffold(
            body: Builder(
              builder: (c) => TextButton(
                onPressed: () => Navigator.push(
                  c,
                  MaterialPageRoute(
                    settings: RouteSettings(
                      name: ObservationPage.routeName(o.id),
                    ),
                    builder: (_) =>
                        ObservationPage(observation: o, store: store),
                  ),
                ),
                child: const Text('Apri foto'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Apri foto'));
      await tester.pumpAndSettle();
      nav.currentState!.push(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('Bivi intermedi')),
        ),
      );
      await tester.pumpAndSettle();
      nav.currentState!.push(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            body: CandidateSelectionButton(
              taxon: const ItalicTaxon(
                scientificName: 'Physcia aipolia',
                italicId: 1717,
              ),
              observation: o,
              store: store,
              path: () => IdentificationPath(
                keyId: 'general',
                answers: {'1': KeyAnswer.a},
                savedAt: DateTime.now(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Torna al diario'), findsNothing);
      await tester.runAsync(
        () => tester.tap(find.text('Scegli questo candidato')),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Torna al diario'), findsOneWidget);
      await tester.tap(find.text('Torna al diario'));
      await tester.pumpAndSettle();
      expect(find.byType(ObservationPage), findsOneWidget);
      expect(find.text('Bivi intermedi'), findsNothing);
      expect(find.byType(CandidateSelectionButton), findsNothing);
      final saved = (await tester.runAsync(store.repository.all))!.single;
      expect(saved.taxonName, 'Physcia aipolia');
      expect(saved.rank, IdentificationRank.species);
      expect(saved.identificationPath!.answers['1'], KeyAnswer.a);
      expect(saved.notes, 'Original notes');
      expect(saved.plotId, 'plot-ref');
      expect(saved.latitude, 45);
    },
  );
}
