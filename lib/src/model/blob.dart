import 'dart:typed_data';

import 'zlib_stub.dart' if (dart.library.io) 'zlib_io.dart' as zlib;

/// Binary data received from or sent to a BLOB element, such as an image.
///
/// {@category Model}
final class IndiBlob {
  /// Creates a BLOB holding [bytes] in [format].
  ///
  /// [size] is the size once decompressed; it defaults to the length of
  /// [bytes].
  IndiBlob(this.bytes, {required this.format, int? size})
      : size = size ?? bytes.length;

  /// The raw data, as sent on the wire (possibly compressed).
  final Uint8List bytes;

  /// The format as a file extension, such as `.fits`, `.jpg`, `.xisf` or
  /// `.fits.z`. A trailing `.z` means the data is zlib-compressed.
  final String format;

  /// The size in bytes of the data once decompressed.
  final int size;

  /// Whether [bytes] is zlib-compressed (the [format] ends with `.z`).
  bool get isCompressed => format.endsWith('.z');

  /// The format without the compression suffix, such as `.fits` for
  /// `.fits.z`.
  String get uncompressedFormat =>
      isCompressed ? format.substring(0, format.length - 2) : format;

  /// Returns the uncompressed data: [bytes] itself when the BLOB is not
  /// compressed.
  ///
  /// Throws an [UnsupportedError] on the web, where zlib is not available
  /// synchronously. Disable compression in the driver there, for example
  /// with the camera's `CCD_COMPRESSION` property.
  Uint8List decompress() => isCompressed ? zlib.inflate(bytes) : bytes;

  @override
  String toString() => 'IndiBlob($format, ${bytes.length} bytes)';
}
