@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:indi/indi.dart';
import 'package:test/test.dart';

void main() {
  test('decompressing is not supported on the web', () {
    final blob = IndiBlob(Uint8List(4), format: '.fits.z');
    expect(blob.decompress, throwsUnsupportedError);
  });
}
