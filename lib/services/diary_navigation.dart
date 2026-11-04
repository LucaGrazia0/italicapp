import 'package:flutter/widgets.dart';

class DiaryNavigation {
  static String observationRoute(String id) => '/diary/observation/$id';
  static void returnToObservation(BuildContext context, String id) {
    final target = observationRoute(id);
    Navigator.of(
      context,
    ).popUntil((route) => route.settings.name == target || route.isFirst);
  }
}
