import 'dart:convert';
import 'scientific_data.dart';
import 'revision_cache.dart';

class ItalicTaxon {
  const ItalicTaxon({
    required this.scientificName,
    this.italicId,
    this.synonyms = const [],
    this.distribution,
    this.description,
    this.note,
    this.growthForm,
    this.substrata,
    this.photobiont,
    this.reproductiveStrategy,
    this.climaticAffinity,
    this.belts = const {},
    this.ecologicalScales = const {},
    this.sourceUrl,
    this.ecologyCodes = const {},
    this.ecologicalTraits = const {},
  });

  final String scientificName;
  final int? italicId;
  final List<String> synonyms;
  final String? distribution,
      description,
      note,
      growthForm,
      substrata,
      photobiont,
      reproductiveStrategy,
      climaticAffinity,
      sourceUrl;
  final Map<String, dynamic> belts;
  final Map<String, dynamic> ecologicalScales;
  final Map<String, String> ecologyCodes;
  final Map<String, String> ecologicalTraits;

  factory ItalicTaxon.fromMap(Map<String, dynamic> m) => ItalicTaxon(
    scientificName: m['scientificName']?.toString() ?? '',
    italicId: (m['italicId'] as num?)?.toInt(),
    synonyms: (m['synonyms'] as List? ?? const [])
        .map((e) => e.toString())
        .toList(),
    distribution: m['distribution']?.toString(),
    description: m['description']?.toString(),
    note: m['note']?.toString(),
    growthForm: m['growthForm']?.toString(),
    substrata: m['substrata']?.toString(),
    photobiont: m['photobiont']?.toString(),
    reproductiveStrategy: m['reproductiveStrategy']?.toString(),
    climaticAffinity: m['climaticAffinity']?.toString(),
    belts: Map<String, dynamic>.from(m['belts'] as Map? ?? const {}),
    ecologicalScales: Map<String, dynamic>.from(
      m['ecologicalScales'] as Map? ?? const {},
    ),
    sourceUrl: m['sourceUrl']?.toString(),
    ecologyCodes: (m['ecologyCodes'] as Map? ?? const {}).map(
      (k, v) => MapEntry(k.toString(), v.toString()),
    ),
    ecologicalTraits: (m['ecologicalTraits'] as Map? ?? const {}).map(
      (k, v) => MapEntry(k.toString(), v.toString()),
    ),
  );
}

class ItalicSnapshotMetadata {
  const ItalicSnapshotMetadata({
    required this.source,
    required this.sourceName,
    required this.count,
    required this.status,
    this.generatedAt,
    this.ecologyTaxa = 0,
  });
  final String source, sourceName, status;
  final int count;
  final DateTime? generatedAt;
  final int ecologyTaxa;
}

class ItalicReferenceRepository {
  static final _cache = RevisionCache<ItalicReferenceRepository>();
  List<ItalicTaxon> _taxa = const [];
  ItalicSnapshotMetadata? metadata;
  List<ItalicTaxon> get taxa => _taxa;

  Future<void> load({int? revision}) async {
    final snapshot = await _cache.load((key) async {
      final repository = ItalicReferenceRepository();
      await repository._read(revision: key);
      return repository;
    }, revision: revision);
    _taxa = snapshot.taxa;
    metadata = snapshot.metadata;
  }

  Future<void> _read({int? revision}) async {
    final raw = await ScientificData.loadString(
      'assets/italic/italic_checklist.json',
      revision: revision,
    );
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final meta = Map<String, dynamic>.from(data['metadata'] as Map? ?? {});
    _taxa =
        (data['taxa'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => ItalicTaxon.fromMap(Map<String, dynamic>.from(e)))
            .where((e) => e.scientificName.isNotEmpty)
            .toList()
          ..sort(
            (a, b) => a.scientificName.toLowerCase().compareTo(
              b.scientificName.toLowerCase(),
            ),
          );
    _taxa = List.unmodifiable(_taxa);
    metadata = ItalicSnapshotMetadata(
      source: meta['source']?.toString() ?? '',
      sourceName: meta['source_name']?.toString() ?? 'ITALIC 8.0',
      count: (meta['count'] as num?)?.toInt() ?? _taxa.length,
      status: meta['status']?.toString() ?? 'unknown',
      ecologyTaxa:
          ((meta['ecology_enrichment'] as Map?)?['matched_taxa'] as num?)
              ?.toInt() ??
          0,
      generatedAt: meta['generated_at'] == null
          ? null
          : DateTime.tryParse(meta['generated_at'].toString()),
    );
  }

  List<ItalicTaxon> search(String query, {int limit = 200}) {
    final q = query.trim().toLowerCase();
    Iterable<ItalicTaxon> x = _taxa;
    if (q.isNotEmpty) {
      x = x.where(
        (t) =>
            t.scientificName.toLowerCase().contains(q) ||
            t.synonyms.any((s) => s.toLowerCase().contains(q)),
      );
    }
    return x.take(limit).toList();
  }
}
