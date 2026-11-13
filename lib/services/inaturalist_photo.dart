import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Pixels only: do not leak original EXIF locations after a map correction or
/// when location sharing is off. Originals in the diary stay untouched.
Future<Uint8List> prepareINaturalistPhoto(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  try {
    final ratio = math.min(
      1.0,
      2048 / math.max(descriptor.width, descriptor.height),
    );
    final codec = await descriptor.instantiateCodec(
      targetWidth: (descriptor.width * ratio).round().clamp(1, 2048),
      targetHeight: (descriptor.height * ratio).round().clamp(1, 2048),
    );
    try {
      final frame = await codec.getNextFrame();
      try {
        final data = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (data == null) throw StateError('Foto non preparata.');
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  } finally {
    descriptor.dispose();
    buffer.dispose();
  }
}
