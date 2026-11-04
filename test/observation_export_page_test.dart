import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:italicapp/pages/observation_export_page.dart';
import 'package:italicapp/services/observation_export.dart';
import 'package:italicapp/models/observation.dart';
import 'observation_export_test.dart' show exampleObservation;

void main() {
  testWidgets(
    'On a phone share uses only selected observations and explicitly enabled GPS/photo',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final o = exampleObservation();
      ShareParams? sent;
      await tester.pumpWidget(
        MaterialApp(
          home: ObservationExportPage(
            observations: [o],
            sender: (p) async {
              sent = p;
              return const ShareResult('', ShareResultStatus.dismissed);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final submit = find.byKey(const ValueKey('share-observations'));
      await tester.scrollUntilVisible(
        submit,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(sent!.files, isNull);
      expect(sent!.text, isNot(contains('45.1234567')));
      expect(find.text('Condivisione annullata.'), findsOneWidget);
      final format = find.byKey(const ValueKey('export-format'));
      await tester.scrollUntilVisible(
        format,
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(format);
      await tester.pumpAndSettle();
      await tester.tap(format);
      await tester.pumpAndSettle();
      await tester.tap(find.text(ObservationExportFormat.geojson.label).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('export-gps')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('export-photo')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        submit,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(sent!.files!.length, 2);
      final data = jsonDecode(
        utf8.decode(await sent!.files!.first.readAsBytes()),
      );
      expect(data['features'][0]['geometry']['coordinates'], [
        -11.7654321,
        45.1234567,
      ]);
      expect(sent!.fileNameOverrides!.first, endsWith('.geojson'));
      expect(sent!.sharePositionOrigin!.width, greaterThan(0));
      expect(o.taxonName, 'Physcia adscendens H. Olivier');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Selection can be cleared, preventing accidental export of the entire diary',
    (tester) async {
      final o = exampleObservation();
      await tester.pumpWidget(
        MaterialApp(
          home: ObservationExportPage(
            observations: [
              o,
              Observation.fromMap({
                ...o.toMap(),
                'id': 'sample-2',
                'taxonName': 'Secondo campione',
              }),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scegli osservazioni'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nessuna'));
      await tester.pumpAndSettle();
      expect(find.text('0 osservazioni selezionate'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('share-observations')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey('share-observations')),
      );
      expect(button.onPressed, isNull);
    },
  );
}
