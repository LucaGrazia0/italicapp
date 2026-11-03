import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:italicapp/data/observation_database_native.dart';
import 'package:italicapp/data/observation_repository.dart';
import 'package:italicapp/data/character_review_repository.dart';
import 'package:italicapp/data/italic_reference_repository.dart';
import 'package:italicapp/models/observation.dart';
import 'package:italicapp/models/identification_path.dart';
import 'package:italicapp/models/character_review.dart';

void main() {
  test(
    'Native observations, photos and identification paths survive closing and reopening',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'italic-native-observations-',
      );
      addTearDown(() => folder.delete(recursive: true));
      final repository = ObservationRepository(
        factory: nativeDatabaseFactoryAt(folder.path),
      );
      final observation = Observation(
        id: 'native-test',
        createdAt: DateTime.utc(2026, 11, 2),
        latitude: 45.1,
        longitude: 11.2,
        horizontalAccuracy: 4,
        photoBytes: Uint8List.fromList([0, 7, 255, 13]),
        photoName: 'sample.jpg',
        notes: 'Note di prova',
        identificationPath: IdentificationPath(
          keyId: 'italic-general-reconstructed-v1',
          answers: const {},
          selections: const {
            '_genus': 'Peltigera',
            '_trait:growthForm': 'Fol',
            'lead_1': 'lead_2',
          },
          savedAt: DateTime.utc(2026, 11, 2),
        ),
      );
      await repository.save(observation);
      await repository.close();
      final reopened = ObservationRepository(
        factory: nativeDatabaseFactoryAt(folder.path),
      );
      final saved = (await reopened.all()).single;
      expect(saved.toMap(), observation.toMap());
      expect(saved.photoBytes, observation.photoBytes);
      await reopened.delete(saved.id);
      await reopened.close();
      final again = ObservationRepository(
        factory: nativeDatabaseFactoryAt(folder.path),
      );
      expect(await again.all(), isEmpty);
      await again.close();
    },
  );
  test(
    'Native character reviews persist and enforce revision history after reopening',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'italic-native-reviews-',
      );
      addTearDown(() => folder.delete(recursive: true));
      final raw =
          (jsonDecode(
                    File(
                      'assets/italic/italic_checklist.json',
                    ).readAsStringSync(),
                  )['taxa']
                  as List)
              .cast<Map>()
              .singleWhere((r) => r['italicId'] == 1717);
      final taxon = ItalicTaxon.fromMap(Map<String, dynamic>.from(raw));
      final review = CharacterReview.create(
        taxon: taxon,
        characterId: 'soralia_shape',
        value: 'hood',
        status: 'reviewed',
        reviewer: 'Test locale',
        quote: 'hood-shaped soralia',
      );
      final repository = CharacterReviewRepository(
        factory: nativeDatabaseFactoryAt(folder.path),
      );
      await repository.save(review, taxon);
      await repository.close();
      final reopened = CharacterReviewRepository(
        factory: nativeDatabaseFactoryAt(folder.path),
      );
      expect((await reopened.all()).single.toMap(), review.toMap());
      await expectLater(
        reopened.save(review, taxon),
        throwsA(isA<ReviewConflict>()),
      );
      final next = CharacterReview.create(
        taxon: taxon,
        characterId: 'soralia_shape',
        value: 'unknown',
        status: 'draft',
        reviewer: 'Test locale',
        quote: '',
        previous: review,
      );
      await reopened.save(next, taxon);
      await reopened.close();
      final again = CharacterReviewRepository(
        factory: nativeDatabaseFactoryAt(folder.path),
      );
      expect((await again.all()).map((r) => r.id).toSet(), {
        review.id,
        next.id,
      });
      await again.close();
    },
  );
}
