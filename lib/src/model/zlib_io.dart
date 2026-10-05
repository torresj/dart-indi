import 'dart:io';
import 'dart:typed_data';

/// Decompresses zlib [data].
Uint8List inflate(Uint8List data) {
  final result = zlib.decode(data);
  return result is Uint8List ? result : Uint8List.fromList(result);
}
