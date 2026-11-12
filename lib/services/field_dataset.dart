import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import '../app_store.dart';
import '../models/field_plot.dart';
import '../models/observation.dart';
import 'diary_filter.dart';
import 'observation_export.dart';
import 'xlsx_writer.dart';

/// Immutable export selection: the same filters as diary and map. Plot photos
/// use the sampling event date, and inherit only explicitly documented position.
class FieldDataset {
  FieldDataset({required this.observations, required this.plots, this.regions});
  factory FieldDataset.fromStore(AppStore store, {String? plotId}) =>
      FieldDataset(
        observations: [
          for (final o
              in (plotId == null
                  ? store.filteredObservations
                  : store.photosForPlot(plotId)))
            copyForExport(o),
        ],
        plots: plotId == null
            ? store.filteredPlots
            : [if (store.plotById(plotId) != null) store.plotById(plotId)!],
        regions: store.regions,
      );
  static Observation copyForExport(
    Observation o, [
    Map<String, Object?> changes = const {},
  ]) =>
      Observation.fromMap({...o.toMap(), ...changes, 'photoBytes': null})
        ..photoBytes = o.photoBytes;
  final List<Observation> observations;
  final List<FieldPlot> plots;
  final ItalianRegions? regions;
  List<Observation> get photos =>
      observations.where((o) => o.photoBytes?.isNotEmpty == true).toList();
  FieldPlot? plotFor(Observation o) {
    for (final p in plots) {
      if (p.id == o.plotId) return p;
    }
    return null;
  }

  Observation effective(Observation o) {
    final p = plotFor(o);
    if (p == null) return o;
    return copyForExport(o, {
      'observedAt': p.sampledAt.toIso8601String(),
      'substrate': o.substrate ?? p.substrate,
      if (!o.hasPosition && p.hasPosition) ...{
        'latitude': p.latitude,
        'longitude': p.longitude,
        'horizontalAccuracy': p.horizontalAccuracy,
        'coordinateUncertaintyInMeters': p.coordinateUncertaintyInMeters,
        'seaLevelAltitude': p.seaLevelAltitude,
        'seaLevelAccuracy': p.seaLevelAccuracy,
        'altitudeReference': p.altitudeReference,
        'positionProvider': 'plot',
      },
    });
  }

  static const columns = [
    'occurrenceID',
    'eventID',
    'basisOfRecord',
    'scientificName',
    'verbatimIdentification',
    'taxonRank',
    'locality',
    'substratum',
    'specific_substratum',
    'recordedBy',
    'identifiedBy',
    'year',
    'eventDate',
    'data_type',
    'organismQuantity',
    'organismQuantityType',
    'stateProvince',
    'county',
    'municipality',
    'decimalLatitude',
    'decimalLongitude',
    'geodeticDatum',
    'coordinateUncertaintyInMeters',
    'minimumElevationInMeters',
    'maximumElevationInMeters',
    'occurrenceRemarks',
    'identificationVerificationStatus',
    'associatedMedia',
    'dynamicProperties',
    'Dem elevation (m)',
    'Source',
    'short_source',
    'Source type',
    'Source year',
    'associatedReferences',
    'Plot id',
    'Habitat',
    'Protect area',
    'Main drainage basin',
    'Secondary drainage basin',
    'Soiusa major sector',
    'Soiusa section',
    'Soiusa subsection',
    'Soiusa supergroup',
    'Soiusa group',
    'Natura 2000 code',
    'Natura 2000 site',
    'SIC/ZSC',
    'ZPS',
    'specimenID',
    'new_identification',
  ];
  List<List<Object?>> occurrences({
    bool includeGps = false,
    String recordedBy = '',
    String identifiedBy = '',
  }) {
    final rows = <List<Object?>>[columns];
    final firstBySpecies = <String>{};
    List<Object?> row(Observation input, {PlotSpecies? inventory}) {
      final o = effective(input), p = plotFor(input);
      final position = includeGps && o.hasPosition;
      final region = position ? regions?.at(o.latitude, o.longitude) : null;
      final quantityKey = '${p?.id}:${inventory?.italicId ?? inventory?.key}';
      final quantity = inventory != null && firstBySpecies.add(quantityKey)
          ? inventory.abundance
          : '';
      return [
        'urn:italicgo:occurrence:${o.id}',
        p == null ? 'urn:italicgo:event:${o.id}' : 'urn:italicgo:plot:${p.id}',
        'HumanObservation',
        o.rank == IdentificationRank.species ? o.taxonName : null,
        o.taxonName,
        o.rank == IdentificationRank.undetermined ? null : o.rank.name,
        p?.name ?? o.sourcePlotName,
        o.substrate,
        '',
        recordedBy.trim(),
        o.taxonName == null ? '' : identifiedBy.trim(),
        o.eventDate.year,
        o.eventDate.toIso8601String(),
        p == null ? 'observation' : 'vegetation-plot data',
        quantity,
        '',
        region?.name,
        '',
        '',
        position ? o.latitude : null,
        position ? o.longitude : null,
        position ? 'WGS84' : null,
        position ? o.positionUncertaintyInMeters : null,
        position ? o.seaLevelAltitude : null,
        position ? o.seaLevelAltitude : null,
        [
          o.notes,
          if (inventory?.notes.isNotEmpty == true) inventory!.notes,
        ].where((s) => s.isNotEmpty).join('\n'),
        'unverified',
        o.photoBytes == null ? '' : photoFileName(o),
        jsonEncode({
          'application': 'Italic Go',
          'italicId': o.taxonItalicId,
          if (o.identificationMethod != null)
            'identificationMethod': o.identificationMethod,
          if (p != null) ...{'plotAreaM2': p.areaM2, 'plotNotes': p.notes},
          if (o.identificationPath != null)
            'identificationPath': o.identificationPath!.toMap(),
          if (quantity.isNotEmpty) 'quantityMethod': 'unspecified',
          if (position) ...{
            'positionProvider': o.positionProvider,
            'altitudeReference': o.altitudeReference,
            'seaLevelAccuracy': o.seaLevelAccuracy,
            if (o.coordinateUncertaintyInMeters != null)
              'coordinateUncertaintySource': 'user_estimate',
          },
          if (o.sourcePlotId != null) 'sourcePlotId': o.sourcePlotId,
        }),
        null,
        'Italic Go · unpublished',
        'unpublished',
        'unpublished',
        o.eventDate.year,
        '',
        p?.id ?? o.sourcePlotId,
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
      ];
    }

    for (final o in observations) {
      final p = plotFor(o);
      PlotSpecies? s;
      if (o.rank == IdentificationRank.species && p != null) {
        for (final item in p.species) {
          if (sameSpecies(o, item)) {
            s = item;
            break;
          }
        }
      }
      rows.add(row(o, inventory: s));
    }
    for (final p in plots) {
      for (final s in p.species) {
        if (observations.any(
          (o) =>
              o.plotId == p.id &&
              o.rank == IdentificationRank.species &&
              sameSpecies(o, s),
        )) {
          continue;
        }
        rows.add(
          row(
            Observation(
              id: 'plot-species:${p.id}:${s.italicId ?? s.key}',
              createdAt: p.sampledAt,
              rank: IdentificationRank.species,
              taxonName: s.name,
              taxonItalicId: s.italicId,
              plotId: p.id,
            ),
            inventory: s,
          ),
        );
      }
    }
    return rows;
  }

  static bool sameSpecies(Observation o, PlotSpecies s) =>
      s.italicId != null && o.taxonItalicId == s.italicId ||
      o.taxonName?.trim().toLowerCase() == s.key;
  static String photoFileName(Observation o) {
    var extension = (o.photoName ?? '').split('.').last.toLowerCase();
    if (!{'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'}.contains(extension)) {
      final b = o.photoBytes;
      extension = b != null && b.length > 3 && b[0] == 0x89 && b[1] == 0x50
          ? 'png'
          : 'jpg';
    }
    return 'photos/${o.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}.$extension';
  }

  Map<String, List<List<Object?>>> workbook({
    bool includeGps = false,
    String recordedBy = '',
    String identifiedBy = '',
  }) => {
    'Occurrences': occurrences(
      includeGps: includeGps,
      recordedBy: recordedBy,
      identifiedBy: identifiedBy,
    ),
    'Plots': [
      [
        'eventID',
        'name',
        'eventDate',
        'areaM2',
        'substratum',
        'eventRemarks',
        'decimalLatitude',
        'decimalLongitude',
        'coordinateUncertaintyInMeters',
      ],
      for (final p in plots)
        [
          'urn:italicgo:plot:${p.id}',
          p.name,
          p.sampledAt.toIso8601String(),
          p.areaM2,
          p.substrate,
          p.notes,
          includeGps && p.hasPosition ? p.latitude : null,
          includeGps && p.hasPosition ? p.longitude : null,
          includeGps && p.hasPosition ? p.positionUncertaintyInMeters : null,
        ],
    ],
    'Lista specie plot': [
      [
        'eventID',
        'scientificName',
        'italicId',
        'organismQuantity',
        'organismQuantityType',
        'occurrenceRemarks',
      ],
      for (final p in plots)
        for (final s in p.species)
          [
            'urn:italicgo:plot:${p.id}',
            s.name,
            s.italicId,
            s.abundance,
            '',
            s.notes,
          ],
    ],
    'Campi': [
      ['campo', 'descrizione'],
      [
        'Fonte campi DoLichens',
        'https://italic.units.it/dolichens/?c=60&procedure=base&t=59',
      ],
      ['Darwin Core', 'https://dwc.tdwg.org/terms/'],
      [
        'coordinateUncertaintyInMeters',
        'Raggio d’incertezza in metri: stima manuale quando indicata sulla mappa; altrimenti accuratezza orizzontale fornita dal dispositivo. Vuoto se sconosciuto.',
      ],
      [
        'substratum / specific_substratum / data_type',
        'Campi aggiuntivi DoLichens, non termini Darwin Core.',
      ],
      [
        'scientificName',
        'Nome determinato a livello di specie dalla checklist ITALIC; nessuna validazione tassonomica esterna aggiuntiva.',
      ],
      [
        'eventDate',
        'Per i plot è la data del rilievo; per le foto singole è la data disponibile nel diario.',
      ],
      [
        'organismQuantityType',
        'Non specificato: non si assume che l’abbondanza inserita sia un numero di individui o una percentuale.',
      ],
      [
        'minimumElevationInMeters / maximumElevationInMeters',
        'Quota sul livello del mare disponibile; non quota ellissoidica.',
      ],
      [
        'stateProvince',
        'Calcolato localmente da confini generalizzati Istat 2026, CC BY 4.0. Provincia e comune non dedotti.',
      ],
      [
        'associatedMedia',
        'Nome del file allegato se si includono le foto; non è un URL pubblico.',
      ],
      [
        'identificationVerificationStatus',
        'unverified: determinazione personale, non convalida di un esperto.',
      ],
      [
        'Foto e lista specie',
        'Le foto sono occorrenze individuali. Le specie manuali già rappresentate da foto determinate non creano righe aggiuntive. L’abbondanza compare solo sulla prima foto della specie nel plot.',
      ],
    ],
  };
  List<Map<String, Object?>> records({
    bool includeGps = false,
    String recordedBy = '',
    String identifiedBy = '',
  }) => [
    for (final row in occurrences(
      includeGps: includeGps,
      recordedBy: recordedBy,
      identifiedBy: identifiedBy,
    ).skip(1))
      {for (var i = 0; i < columns.length; i++) columns[i]: row[i]},
  ];
  String completeNotes(Map<String, Object?> record) => [
    'Italic Go · dati DoLichens / Darwin Core',
    for (final entry in record.entries.where(
      (e) => e.value != null && e.value.toString().isNotEmpty,
    ))
      '${entry.key}: ${entry.value}',
    'Determinazione personale da verificare; i nomi ITALIC possono differire dalla tassonomia iNaturalist.',
  ].join('\n');
  List<List<Object?>> inaturalistRows({
    bool includeGps = false,
    String recordedBy = '',
    String identifiedBy = '',
  }) => [
    [
      'species_guess',
      'observed_on_string',
      'description',
      'place_guess',
      'latitude',
      'longitude',
      'positional_accuracy',
      'tag_list',
    ],
    for (final r in records(
      includeGps: includeGps,
      recordedBy: recordedBy,
      identifiedBy: identifiedBy,
    ))
      [
        r['scientificName'] ?? r['verbatimIdentification'],
        r['eventDate'],
        completeNotes(r),
        r['locality'],
        r['decimalLatitude'],
        r['decimalLongitude'],
        r['coordinateUncertaintyInMeters'],
        'Italic Go',
      ],
  ];
  ObservationExportFile inaturalistPackage({
    bool includeGps = false,
    String recordedBy = '',
    String identifiedBy = '',
  }) {
    final archive = Archive();
    void add(String name, Uint8List bytes) =>
        archive.addFile(ArchiveFile(name, bytes.length, bytes));
    add(
      'DoLichens-DarwinCore.xlsx',
      writeXlsx(
        workbook(
          includeGps: includeGps,
          recordedBy: recordedBy,
          identifiedBy: identifiedBy,
        ),
      ),
    );
    add(
      'DoLichens-DarwinCore.csv',
      writeCsv(
        occurrences(
          includeGps: includeGps,
          recordedBy: recordedBy,
          identifiedBy: identifiedBy,
        ),
      ),
    );
    add(
      'iNaturalist-import.csv',
      writeCsv(
        inaturalistRows(
          includeGps: includeGps,
          recordedBy: recordedBy,
          identifiedBy: identifiedBy,
        ),
      ),
    );
    for (final o in photos) {
      add(photoFileName(o), o.photoBytes!);
    }
    final rows = records(
      includeGps: includeGps,
      recordedBy: recordedBy,
      identifiedBy: identifiedBy,
    );
    for (var i = 0; i < rows.length; i++) {
      archive.addFile(
        ArchiveFile.string(
          'schede/occurrence-${i + 1}.txt',
          completeNotes(rows[i]),
        ),
      );
    }
    archive.addFile(
      ArchiveFile.string(
        'LEGGIMI.txt',
        'PACCHETTO COMPLETO ITALIC GO / DOLICHENS / INATURALIST\n'
            'Il ZIP NON viene importato direttamente dall’app iNaturalist. Estrai prima i file.\n'
            'APP: condividi una foto e copia la sua scheda completa nelle note dell’osservazione prima di pubblicarla.\n'
            'SITO: nel caricamento iNaturalist scegli More Import Options / CSV e seleziona iNaturalist-import.csv. Controlla corrispondenza delle colonne, data, taxon e coordinate. Allega poi le foto alle osservazioni corrispondenti usando associatedMedia/occurrenceID; i percorsi locali nel CSV NON allegano automaticamente le immagini. Evita di creare una seconda osservazione per la stessa foto.\n'
            'description conserva tutti i campi DoLichens disponibili come testo; non li trasforma automaticamente in Observation Fields strutturati. Per analisi usa il file Darwin Core originale.\n'
            'Le celle vuote significano dato mancante. DEM, comuni, province, aree protette e SOIUSA non sono inventati. specimenID resta vuoto per osservazioni fotografiche.\n'
            'Coordinate nella tabella: ${includeGps ? "incluse" : "escluse"}. Le immagini originali possono contenere metadati propri. Nessuna pubblicazione automatica.\n'
            'Osservazioni riferite al tuo account iNaturalist; recordedBy/identifiedBy nelle note non cambiano il proprietario del record.\n'
            'https://italic.units.it/dolichens/?c=60&procedure=base&t=59\n'
            'https://www.inaturalist.org/observations/upload',
      ),
    );
    return ObservationExportFile(
      'Italic-Go-iNaturalist-DoLichens.zip',
      'application/zip',
      Uint8List.fromList(ZipEncoder().encode(archive)),
    );
  }

  ObservationExportFile export({
    required bool excel,
    bool includeGps = false,
    bool includePhotos = false,
    String recordedBy = '',
    String identifiedBy = '',
  }) {
    final tables = workbook(
      includeGps: includeGps,
      recordedBy: recordedBy,
      identifiedBy: identifiedBy,
    );
    final name = 'Italic-Go${plots.length == 1 ? '-plot' : '-diario'}';
    final bytes = excel ? writeXlsx(tables) : writeCsv(tables['Occurrences']!);
    final extension = excel ? 'xlsx' : 'csv';
    if (!includePhotos) {
      return ObservationExportFile(
        '$name.$extension',
        excel
            ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
            : 'text/csv',
        bytes,
      );
    }
    final archive = Archive()
      ..addFile(ArchiveFile('$name.$extension', bytes.length, bytes));
    if (!excel) {
      for (final entry in tables.entries.where((e) => e.key != 'Occurrences')) {
        final data = writeCsv(entry.value);
        archive.addFile(ArchiveFile('${entry.key}.csv', data.length, data));
      }
    }
    for (final o in photos) {
      archive.addFile(
        ArchiveFile(photoFileName(o), o.photoBytes!.length, o.photoBytes!),
      );
    }
    archive.addFile(
      ArchiveFile.string(
        'LEGGIMI.txt',
        'Esportazione Italic Go. Coordinate ${includeGps ? "incluse" : "escluse dalla tabella"}. Le foto originali possono conservare metadati propri. Nessuna pubblicazione online automatica.',
      ),
    );
    return ObservationExportFile(
      '$name.zip',
      'application/zip',
      Uint8List.fromList(ZipEncoder().encode(archive)),
    );
  }
}
