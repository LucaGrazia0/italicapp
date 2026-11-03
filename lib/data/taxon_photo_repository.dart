import 'dart:convert';
import 'package:flutter/services.dart';
import 'italic_reference_repository.dart';

class TaxonPhoto {
  const TaxonPhoto({
    required this.italicId,
    required this.scientificName,
    required this.asset,
    required this.pageUrl,
    required this.originalUrl,
    required this.credit,
    required this.width,
    required this.height,
  });
  final int italicId, width, height;
  final String scientificName, asset, credit;
  final Uri pageUrl, originalUrl;

  factory TaxonPhoto.fromMap(Map<String, dynamic> map) {
    final id = map['italicId'] as int;
    final page = Uri.parse(map['pageUrl'] as String);
    final original = Uri.parse(map['originalUrl'] as String);
    final asset = map['asset'] as String;
    if (id <= 0 ||
        page.scheme != 'https' ||
        page.host != 'italic.units.it' ||
        page.path != '/dolichens/index.php' ||
        page.queryParameters['procedure'] != 'taxonpage' ||
        page.queryParameters['num'] != '$id' ||
        original.scheme != 'https' ||
        original.host != 'italic.units.it' ||
        !original.path.startsWith('/flora/images/species/images/') ||
        !RegExp(r'^assets/photos/[a-f0-9]{24}\.webp$').hasMatch(asset) ||
        map['photoOrder'] != 1 ||
        map['sourceName'] != map['scientificName'] ||
        (map['width'] as int) <= 0 ||
        (map['height'] as int) <= 0) {
      throw const FormatException('Abbinamento fotografico non valido.');
    }
    return TaxonPhoto(
      italicId: id,
      scientificName: map['scientificName'] as String,
      asset: asset,
      pageUrl: page,
      originalUrl: original,
      credit: map['credit'] as String,
      width: map['width'] as int,
      height: map['height'] as int,
    );
  }
}

class TaxonPhotoRepository {
  TaxonPhotoRepository.fromMap(Map<String, dynamic> map) {
    if (map['schemaVersion'] != 1) {
      throw const FormatException('Catalogo fotografico non valido.');
    }
    for (final raw in (map['photos'] as List).cast<Map>()) {
      final photo = TaxonPhoto.fromMap(Map<String, dynamic>.from(raw));
      if (_photos.containsKey(photo.italicId)) {
        throw const FormatException('ID fotografico duplicato.');
      }
      _photos[photo.italicId] = photo;
    }
  }
  final _photos = <int, TaxonPhoto>{};
  static Future<TaxonPhotoRepository>? _loading;
  static Future<TaxonPhotoRepository> load() => _loading ??= _load();
  static Future<TaxonPhotoRepository> _load() async {
    try {
      final text = await rootBundle.loadString(
        'assets/italic/species_photos_v1.json',
      );
      return TaxonPhotoRepository.fromMap(
        jsonDecode(text) as Map<String, dynamic>,
      );
    } catch (_) {
      _loading = null;
      rethrow;
    }
  }

  TaxonPhoto? forTaxon(ItalicTaxon taxon) {
    final photo = _photos[taxon.italicId];
    // A later scientific data update must not attach an old photo to a renamed ID.
    return photo?.scientificName == taxon.scientificName ? photo : null;
  }
}
