import 'package:flutter/foundation.dart';
import 'field_dataset.dart';
import 'observation_export.dart';

class DatasetExportJob {
  const DatasetExportJob(
    this.dataset, {
    this.forINaturalist = false,
    this.excel = true,
    this.includeGps = false,
    this.includePhotos = false,
    this.recordedBy = '',
    this.identifiedBy = '',
  });
  final FieldDataset dataset;
  final bool forINaturalist, excel, includeGps, includePhotos;
  final String recordedBy, identifiedBy;
}

/// Mobile platforms build ZIP / Excel files away from the UI isolate. The
/// callback captures neither a page nor the store/database. Web uses compute's
/// supported same-thread fallback and keeps the existing export format.
Future<ObservationExportFile> buildDatasetExport(DatasetExportJob job) =>
    compute(_build, job, debugLabel: 'Italic Go export');

ObservationExportFile _build(DatasetExportJob job) => job.forINaturalist
    ? job.dataset.inaturalistPackage(
        includeGps: job.includeGps,
        recordedBy: job.recordedBy,
        identifiedBy: job.identifiedBy,
      )
    : job.dataset.export(
        excel: job.excel,
        includeGps: job.includeGps,
        includePhotos: job.includePhotos,
        recordedBy: job.recordedBy,
        identifiedBy: job.identifiedBy,
      );
