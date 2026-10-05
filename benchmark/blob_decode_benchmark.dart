// Measures how fast large images are decoded from the wire.
//
// Run with: dart run benchmark/blob_decode_benchmark.dart
// ignore_for_file: avoid_print

import 'dart:typed_data';

import 'package:indi/protocol.dart';

void main() {
  const megabytes = 50;
  final image = Uint8List(megabytes * 1024 * 1024);
  for (var i = 0; i < image.length; i++) {
    image[i] = (i * 2654435761) >> 24 & 0xFF;
  }
  final wire = encodeIndiCommandChunks(SetBlobVector(
    device: 'CCD Simulator',
    name: 'CCD1',
    elements: [OneBlob(name: 'CCD1', format: '.fits', data: image)],
  )).expand((chunk) => chunk).toList();
  final bytes = Uint8List.fromList(wire);

  // Socket-sized chunks, as dart:io delivers them.
  const chunkSize = 64 * 1024;
  for (var run = 0; run < 5; run++) {
    final stopwatch = Stopwatch()..start();
    IndiCommand? decoded;
    final decoder = IndiStreamDecoder(
      onCommand: (command) => decoded = command,
      onError: (error) => throw error,
    );
    for (var start = 0; start < bytes.length; start += chunkSize) {
      final end =
          start + chunkSize < bytes.length ? start + chunkSize : bytes.length;
      decoder.add(Uint8List.sublistView(bytes, start, end));
    }
    decoder.close();
    stopwatch.stop();
    final blob = (decoded! as SetBlobVector).elements.single;
    assert(blob.data.length == image.length);
    final seconds = stopwatch.elapsedMicroseconds / 1e6;
    print(
        'Run ${run + 1}: ${megabytes}MB image (${bytes.length ~/ 1024 ~/ 1024}'
        'MB on the wire) decoded in ${(seconds * 1000).toStringAsFixed(0)} ms '
        '(${(megabytes / seconds).toStringAsFixed(0)} MB/s)');
  }
}
