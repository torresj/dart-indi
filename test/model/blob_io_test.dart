@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:indi/indi.dart';
import 'package:test/test.dart';

void main() {
  test('decompresses zlib-compressed images (.fits.z)', () {
    final image = Uint8List.fromList(
      List.generate(10000, (i) => i % 7),
    );
    final compressed = Uint8List.fromList(zlib.encode(image));
    final blob = IndiBlob(compressed, format: '.fits.z', size: image.length);
    expect(compressed.length, lessThan(image.length));
    expect(blob.decompress(), image);
  });
}
