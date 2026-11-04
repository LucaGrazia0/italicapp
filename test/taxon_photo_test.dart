import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:italicapp/data/italic_reference_repository.dart';
import 'package:italicapp/data/taxon_photo_repository.dart';
import 'package:italicapp/widgets/taxon_photo_card.dart';
import 'package:url_launcher/link.dart';

void main() {
  late Map<String, dynamic> raw;
  late TaxonPhotoRepository photos;
  late List<ItalicTaxon> reference;
  setUpAll(() {
    raw =
        jsonDecode(
              File('assets/italic/species_photos_v1.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    photos = TaxonPhotoRepository.fromMap(raw);
    final source =
        jsonDecode(
              File('assets/italic/italic_checklist.json').readAsStringSync(),
            )
            as Map;
    reference = (source['taxa'] as List)
        .cast<Map>()
        .map((r) => ItalicTaxon.fromMap(Map<String, dynamic>.from(r)))
        .toList();
  });
  ItalicTaxon ramalina() => reference.singleWhere((t) => t.italicId == 3072);

  test(
    'Every bundled photo matches its checklist ID, page and intact local file',
    () {
      final ids = <int>{};
      for (final item in (raw['photos'] as List).cast<Map>()) {
        final taxon = reference.singleWhere(
          (t) => t.italicId == item['italicId'],
        );
        final photo = photos.forTaxon(taxon)!;
        expect(ids.add(photo.italicId), isTrue);
        expect(photo.pageUrl.queryParameters['num'], '${taxon.italicId}');
        expect(photo.scientificName, taxon.scientificName);
        final bytes = File(photo.asset).readAsBytesSync();
        expect(bytes.length, item['bytes']);
        expect(sha256.convert(bytes).toString(), item['sha256']);
        expect(photo.width, lessThanOrEqualTo(960));
        expect(photo.height, lessThanOrEqualTo(960));
      }
      expect(ids.length, raw['photoTaxa']);
    },
  );

  test(
    'User example links to its exact first DoLichens photograph and credit',
    () {
      final photo = photos.forTaxon(ramalina())!;
      expect(
        photo.originalUrl.path,
        endsWith('RamalinaarseniiSrusvandenBoomMagain1723544305.jpg'),
      );
      expect(photo.pageUrl.queryParameters['num'], '3072');
      expect(photo.credit, contains('CC0'));
      expect(
        photos.forTaxon(
          const ItalicTaxon(scientificName: 'Another species', italicId: 3072),
        ),
        isNull,
      );
      expect(
        photos.forTaxon(
          const ItalicTaxon(scientificName: 'No photo', italicId: -1),
        ),
        isNull,
      );
    },
  );

  test(
    'Wrong page, duplicate ID and unrelated source cannot silently attach photos',
    () {
      Map<String, dynamic> changed() =>
          jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;
      final page = changed();
      (page['photos'] as List).first['pageUrl'] =
          'https://italic.units.it/dolichens/index.php?procedure=taxonpage&num=999999';
      expect(() => TaxonPhotoRepository.fromMap(page), throwsFormatException);
      final duplicate = changed();
      (duplicate['photos'] as List).add((duplicate['photos'] as List).first);
      expect(
        () => TaxonPhotoRepository.fromMap(duplicate),
        throwsFormatException,
      );
      final source = changed();
      (source['photos'] as List).first['sourceName'] = 'Different taxon';
      expect(() => TaxonPhotoRepository.fromMap(source), throwsFormatException);
    },
  );

  testWidgets(
    'Photo renders locally, enlarges and links to the same taxon page',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TaxonPhotoCard(
                taxon: ramalina(),
                repository: Future.value(photos),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final image = tester.widget<Image>(find.byType(Image).first);
      expect(image.image, isA<AssetImage>());
      final link = tester.widget<Link>(find.byType(Link));
      expect(link.uri!.queryParameters['num'], '3072');
      await tester.tap(find.byKey(const ValueKey('taxon-photo-enlarge')));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.text(ramalina().scientificName), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Missing or renamed photo shows an explicit absence with the correct page',
    (tester) async {
      const taxon = ItalicTaxon(scientificName: 'Changed name', italicId: 3072);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaxonPhotoCard(
              taxon: taxon,
              repository: Future.value(photos),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(
        find.text('Foto offline non disponibile per questa scheda.'),
        findsOneWidget,
      );
      expect(
        tester.widget<Link>(find.byType(Link)).uri!.queryParameters['num'],
        '3072',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
