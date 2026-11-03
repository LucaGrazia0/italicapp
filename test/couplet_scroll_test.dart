import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:italicapp/data/italic_reference_repository.dart';
import 'package:italicapp/pages/reconstructed_key_page.dart';
import 'package:italicapp/services/reconstructed_key.dart';

void main() {
  testWidgets(
    'On a phone each choice keeps the next couplet visible, including Back and Undo',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final reference =
          (jsonDecode(
                    File(
                      'assets/italic/italic_checklist.json',
                    ).readAsStringSync(),
                  )['taxa']
                  as List)
              .cast<Map>()
              .map((m) => ItalicTaxon.fromMap(Map<String, dynamic>.from(m)))
              .toList();
      final key = ReconstructedKey.fromMap(
        jsonDecode(File(ReconstructedKey.generalAsset).readAsStringSync())
            as Map,
        reference,
      ).forGenus('Physcia');
      await tester.pumpWidget(
        MaterialApp(home: ReconstructedKeyPage(definition: key)),
      );
      await tester.pumpAndSettle();
      void expectVisible(String title) {
        final rect = tester.getRect(find.text(title));
        expect(rect.top, greaterThan(95));
        expect(rect.bottom, lessThan(360));
        expect(
          find.byKey(const ValueKey('reconstructed-count')),
          findsOneWidget,
        );
      }

      expectVisible('Bivio 1 del tuo percorso');
      final choice = key.nodes[key.root]!.choices.first;
      final button = find.byKey(
        ValueKey('reconstructed-choice-${choice.target}'),
      );
      await tester.scrollUntilVisible(button, 180);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expectVisible('Bivio 2 del tuo percorso');
      final back = find.byKey(const ValueKey('reconstructed-back'));
      await tester.scrollUntilVisible(back, 180);
      await tester.tap(back);
      await tester.pumpAndSettle();
      expectVisible('Bivio 1 del tuo percorso');
      await tester.tap(find.byKey(const ValueKey('reconstructed-undo')));
      await tester.pumpAndSettle();
      expectVisible('Bivio 2 del tuo percorso');
      expect(tester.takeException(), isNull);
    },
  );
}
