import 'dart:ui' as ui;
import 'dart:typed_data';

/// Maximum dimension (width or height) to embed as album art.
const int _kCoverMaxDimension = 1000;

/// Maximum byte size of embedded cover art (400 KB).
const int _kCoverMaxBytes = 400 * 1024;

/// Decodes [bytes] as an image, downscales it if either dimension exceeds
/// [_kCoverMaxDimension], and re-encodes as PNG.
///
/// Returns compressed bytes, or [bytes] unchanged if already small enough
/// or if the image cannot be decoded.
Future<Uint8List> compressCoverArtIfNeeded(Uint8List bytes) async {
  // Already within budget — nothing to do.
  if (bytes.length <= _kCoverMaxBytes) return bytes;

  try {
    // Decode and downscale using Flutter's built-in codec.
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: _kCoverMaxDimension,
      targetHeight: _kCoverMaxDimension,
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;

    // Re-encode as PNG (dart:ui only natively supports PNG output).
    final pngData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();

    if (pngData == null) return bytes;
    final pngBytes = pngData.buffer.asUint8List();

    // Return the downscaled PNG — it will be substantially smaller than the
    // original high-resolution source image.
    return pngBytes;
  } catch (_) {
    // Unsupported format, out of memory, etc. — pass through unchanged.
    return bytes;
  }
}
