import 'package:flutter/foundation.dart';
import 'data/observation_repository.dart';
import 'models/observation.dart';

class AppStore extends ChangeNotifier {
  AppStore(this.repository);
  final ObservationRepository repository;

  bool loading = true;
  List<Observation> observations = [];

  Future<void> init() async {
    observations = await repository.all();
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
