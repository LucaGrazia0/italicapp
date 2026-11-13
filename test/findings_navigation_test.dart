import 'package:italicapp/widgets/field_navigation.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:italicapp/main.dart';
import 'package:italicapp/app_store.dart';
import 'package:italicapp/data/observation_repository.dart';
import 'package:italicapp/models/observation.dart';
import 'package:italicapp/pages/capture_page.dart';
import 'package:italicapp/pages/findings_map_page.dart';
import 'package:italicapp/pages/italic_page.dart';
import 'package:italicapp/pages/settings_page.dart';

class Tiles extends TileProvider {
  final image = MemoryImage(
    File(
      'android/app/src/main/res/mipmap-mdpi/ic_launcher.png',
    ).readAsBytesSync(),
  );
  @override
  ImageProvider getImage(TileCoordinates c, TileLayer options) => image;
}

void main() {
  Future<AppStore> store() async {
    final result = AppStore(
      ObservationRepository(factory: newIdbFactoryMemory()),
    );
    await result.init();
    return result;
  }

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
    'Five navigation buttons are in order; inactive pages load on demand and camera drafts survive',
    (tester) async {
      phone(tester);
      final app = (await tester.runAsync(store))!;
      await tester.pumpWidget(ItalicApp(store: app));
      await tester.pumpAndSettle();
      expect(find.byType(CapturePage, skipOffstage: false), findsNothing);
      expect(find.byType(ItalicPage, skipOffstage: false), findsNothing);
      expect(
        find.descendant(
          of: find.byType(FieldNavigation),
          matching: find.byType(Text),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(FieldNavigation),
          matching: find.text('ITALIC'),
        ),
        findsOneWidget,
      );
      final positions = [
        for (var i = 0; i < 5; i++)
          tester.getCenter(find.byKey(ValueKey('nav-$i'))).dx,
      ];
      expect(positions, [...positions]..sort());
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('nav-1')));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      final notes = find.widgetWithText(TextField, 'Note di campo');
      await tester.scrollUntilVisible(notes, 300);
      await tester.enterText(notes, 'Bozza conservata');
      await tester.tap(find.byKey(const ValueKey('nav-3')));
      await tester.pumpAndSettle();
      expect(find.text('I tuoi ritrovamenti'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nav-1')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Bozza conservata'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nav-4')));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Map groups coincident records, searches species and opens the exact diary observation',
    (tester) async {
      phone(tester);
      final app = (await tester.runAsync(store))!;
      Observation? selected;
      for (final o in [
        Observation(
          id: 'a',
          createdAt: DateTime.now(),
          taxonName: 'Physcia aipolia',
          latitude: 45,
          longitude: 11,
        ),
        Observation(
          id: 'b',
          createdAt: DateTime.now(),
          taxonName: 'Peltigera canina',
          latitude: 45,
          longitude: 11,
        ),
        Observation(
          id: 'c',
          createdAt: DateTime.now(),
          taxonName: 'Cladonia sp.',
        ),
      ]) {
        await tester.runAsync(() => app.save(o));
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FindingsMapPage(
              store: app,
              tileProvider: Tiles(),
              onOpen: (o) => selected = o,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('2 ritrovamenti sulla mappa · 1 senza posizione'),
        findsOneWidget,
      );
      expect(find.byType(MarkerLayer), findsOneWidget);
      final marker = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
      expect(marker.markers.length, 1);
      await tester.tap(
        find.byKey(
          ValueKey(
            'findings-marker-${app.observations.firstWhere((o) => o.hasPosition).id}',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('map-record-a')));
      await tester.pumpAndSettle();
      expect(selected?.id, 'a');
      await tester.enterText(
        find.byKey(const ValueKey('findings-search')),
        'Peltigera',
      );
      await tester.pumpAndSettle();
      expect(find.text('1 ritrovamenti sulla mappa'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('findings-search')),
        'assente',
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Nessun ritrovamento corrisponde'),
        findsOneWidget,
      );
      await tester.enterText(find.byKey(const ValueKey('findings-search')), '');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('findings-list')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('map-record-c')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
