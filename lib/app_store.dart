import 'package:flutter/foundation.dart';
import 'data/observation_repository.dart';
import 'models/observation.dart';
import 'models/field_plot.dart';
import 'data/plot_repository.dart';

class AppStore extends ChangeNotifier {
  AppStore(this.repository, {PlotRepository? plotRepository})
    : plotRepository =
          plotRepository ?? PlotRepository(factory: repository.factory);
  final ObservationRepository repository;
  final PlotRepository plotRepository;
  List<FieldPlot> plots = [];
  String? plotLoadError, plotPhotoRecoveryNotice;
  FieldPlot? plotById(String id) {
    for (final plot in plots) {
      if (plot.id == id) return plot;
    }
    return null;
  }

  List<Observation> photosForPlot(String id) =>
      observations.where((o) => o.plotId == id).toList();

  /// Read-only map entries. A plot's position is never written as a photo GPS fix.
  List<Observation> get mapObservations {
    final byId = {for (final p in plots) p.id: p};
    Observation entry(
      String id,
      DateTime date,
      String? name,
      FieldPlot plot, {
      IdentificationRank rank = IdentificationRank.species,
      int? taxonId,
    }) => Observation(
      id: id,
      createdAt: date,
      taxonName: name,
      rank: rank,
      taxonItalicId: taxonId,
      plotId: plot.id,
      latitude: plot.latitude,
      longitude: plot.longitude,
      seaLevelAltitude: plot.seaLevelAltitude,
      positionProvider: 'plot',
    );
    final result = <Observation>[];
    for (final observation in observations) {
      final plot = byId[observation.plotId];
      result.add(
        !observation.hasPosition && plot?.hasPosition == true
            ? entry(
                observation.id,
                observation.createdAt,
                observation.taxonName,
                plot!,
                rank: observation.rank,
                taxonId: observation.taxonItalicId,
              )
            : observation,
      );
    }
    for (final plot in plots) {
      final confirmed = photosForPlot(
        plot.id,
      ).where((o) => o.rank == IdentificationRank.species);
      for (final species in plot.species) {
        if (confirmed.any(
          (o) =>
              (species.italicId != null &&
                  o.taxonItalicId == species.italicId) ||
              o.taxonName?.trim().toLowerCase() ==
                  species.name.trim().toLowerCase(),
        )) {
          continue;
        }
        result.add(
          entry(
            'plot-species:${plot.id}:${species.italicId ?? species.key}',
            plot.sampledAt,
            species.name,
            plot,
            taxonId: species.italicId,
          ),
        );
      }
    }
    return result;
  }

  List<PlotSpecies> speciesForPlot(FieldPlot plot) {
    final rows = {for (final species in plot.species) species.key: species};
    final ids = {
      for (final species in plot.species)
        if (species.italicId != null) species.italicId!,
    };
    for (final photo in photosForPlot(plot.id)) {
      if (photo.rank != IdentificationRank.species ||
          photo.taxonName?.trim().isNotEmpty != true) {
        continue;
      }
      if (photo.taxonItalicId != null && ids.contains(photo.taxonItalicId)) {
        continue;
      }
      final species = PlotSpecies(
        name: photo.taxonName!,
        italicId: photo.taxonItalicId,
      );
      rows.putIfAbsent(species.key, () => species);
      if (photo.taxonItalicId != null) ids.add(photo.taxonItalicId!);
    }
    return rows.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<void> loadPlots() async {
    try {
      plots = await plotRepository.all();
      plotLoadError = null;
    } catch (_) {
      plotLoadError = 'Impossibile leggere i plot salvati. Riprova.';
    }
    notifyListeners();
  }

  Future<void> savePlot(FieldPlot plot) async {
    if (plotLoadError != null) throw StateError(plotLoadError!);
    await plotRepository.save(plot);
    final i = plots.indexWhere((p) => p.id == plot.id);
    if (i < 0) {
      plots.insert(0, plot);
    } else {
      plots[i] = plot;
    }
    plots.sort((a, b) => b.sampledAt.compareTo(a.sampledAt));
    notifyListeners();
  }

  bool loading = true;
  List<Observation> observations = [];

  Future<void> init() async {
    observations = await repository.all();
    await loadPlots();
    loading = false;
    notifyListeners();
  }

  Future<void> save(Observation o) async {
    await repository.save(o);
    final i = observations.indexWhere((x) => x.id == o.id);
    if (i == -1) {
      observations.insert(0, o);
    } else {
      observations[i] = o;
    }
    observations.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    notifyListeners();
  }

  Future<void> delete(Observation o) async {
    await repository.delete(o.id);
    observations.removeWhere((x) => x.id == o.id);
    notifyListeners();
  }
}
