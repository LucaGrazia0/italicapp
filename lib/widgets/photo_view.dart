import 'package:flutter/material.dart';
import '../models/observation.dart';

class ObservationPhoto extends StatelessWidget {
  const ObservationPhoto(this.observation, {super.key, this.fit = BoxFit.cover});
  final Observation observation;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final bytes = observation.photoBytes;
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(bytes, fit: fit, gaplessPlayback: true);
    }
    return Container(
      color: const Color(0xFFE7EEE9),
      alignment: Alignment.center,
      child: const Icon(Icons.image_outlined, size: 48, color: Color(0xFF547764)),
    );
  }
}
