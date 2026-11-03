import 'dart:math';
import '../data/italic_reference_repository.dart';

class CharacterReview {
  CharacterReview({
    required this.id,
    required this.taxonId,
    required this.scientificName,
    required this.characterId,
    required this.value,
    required this.status,
    required this.reviewer,
    required this.createdAt,
    required this.sourceDescription,
    this.sourceNote = '',
    required this.quote,
    this.notes = '',
    this.parentId,
    required this.version,
  });

  final String id, scientificName, characterId, value, status, reviewer;
  final String sourceDescription, sourceNote, quote, notes;
  final String? parentId;
  final int taxonId, version;
  final DateTime createdAt;
  String get cellKey => '$taxonId:$characterId';
  bool get isReviewed => status == 'reviewed';
  String get statusLabel => switch (status) {
    'reviewed' => 'Revisionato manualmente',
    'clarify' => 'Da chiarire',
    _ => 'Bozza',
  };

  bool matches(ItalicTaxon taxon) =>
      taxon.italicId == taxonId &&
      taxon.scientificName == scientificName &&
      (taxon.description ?? '') == sourceDescription &&
      (taxon.note ?? '') == sourceNote &&
      (value == 'unknown' ||
          value == 'absent' && quote.isEmpty ||
          (quote.isNotEmpty && sourceDescription.contains(quote)));

  Map<String, Object?> toMap() => {
    'schemaVersion': 1,
    'id': id,
    'cellKey': cellKey,
    'taxonId': taxonId,
    'scientificName': scientificName,
    'characterId': characterId,
    'value': value,
    'status': status,
    'reviewer': reviewer,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'sourceDescription': sourceDescription,
    'sourceNote': sourceNote,
    'quote': quote,
    'notes': notes,
    'parentId': parentId,
    'version': version,
  };

  factory CharacterReview.create({
    required ItalicTaxon taxon,
    required String characterId,
    required String value,
    required String status,
    required String reviewer,
    required String quote,
    String notes = '',
    CharacterReview? previous,
  }) {
    final date = DateTime.now().toUtc();
    return CharacterReview(
      id: '${date.microsecondsSinceEpoch}-${Random.secure().nextInt(0x100000000)}',
      taxonId: taxon.italicId!,
      scientificName: taxon.scientificName,
      characterId: characterId,
      value: value,
      status: status,
      reviewer: reviewer.trim(),
      createdAt: date,
      sourceDescription: taxon.description ?? '',
      sourceNote: taxon.note ?? '',
      quote: quote.trim(),
      notes: notes.trim(),
      parentId: previous?.id,
      version: (previous?.version ?? 0) + 1,
    );
  }

  factory CharacterReview.fromMap(Map data) {
    const strings = [
      'id',
      'scientificName',
      'characterId',
      'value',
      'status',
      'reviewer',
      'sourceDescription',
      'quote',
      'notes',
    ];
    if (data['schemaVersion'] != 1 ||
        strings.any((k) => data[k] is! String) ||
        data['taxonId'] is! int ||
        data['version'] is! int ||
        (data['version'] as int) < 1 ||
        !['draft', 'reviewed', 'clarify'].contains(data['status']) ||
        (data['reviewer'] as String).trim().isEmpty ||
        (data['parentId'] != null && data['parentId'] is! String)) {
      throw const FormatException('Invalid review record');
    }
    final date = DateTime.tryParse(data['createdAt']?.toString() ?? '');
    if (date == null) throw const FormatException('Invalid review date');
    final review = CharacterReview(
      id: data['id'],
      taxonId: data['taxonId'],
      scientificName: data['scientificName'],
      characterId: data['characterId'],
      value: data['value'],
      status: data['status'],
      reviewer: data['reviewer'],
      createdAt: date,
      sourceDescription: data['sourceDescription'],
      sourceNote: data['sourceNote'] as String? ?? '',
      quote: data['quote'],
      notes: data['notes'],
      parentId: data['parentId'],
      version: data['version'],
    );
    if (data['cellKey'] != review.cellKey) {
      throw const FormatException('Invalid cell identity');
    }
    return review;
  }
}

class ReviewRegistry {
  ReviewRegistry(Iterable<CharacterReview> input)
    : records = List.unmodifiable(input);
  final List<CharacterReview> records;
  List<CharacterReview> history(int taxonId, String characterId) =>
      records
          .where((r) => r.taxonId == taxonId && r.characterId == characterId)
          .toList()
        ..sort((a, b) {
          final version = b.version.compareTo(a.version);
          return version != 0 ? version : b.id.compareTo(a.id);
        });
  CharacterReview? latest(int taxonId, String characterId) {
    final revisions = history(taxonId, characterId);
    return revisions.isEmpty ? null : revisions.first;
  }
}
