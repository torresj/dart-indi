import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:indi/src/protocol/base64_decoder.dart';
import 'package:test/test.dart';

void main() {
  group('Base64ByteDecoder', () {
    test('matches dart:convert for every length and chunking', () {
      final random = Random(7);
      for (var length = 0; length < 70; length++) {
        final data = Uint8List.fromList(
          List.generate(length, (_) => random.nextInt(256)),
        );
        final encoded = ascii.encode(base64Encode(data));
        for (final chunkSize in [1, 2, 3, 5, 64]) {
          final decoder = Base64ByteDecoder();
          for (var i = 0; i < encoded.length; i += chunkSize) {
            decoder.add(encoded, i, min(encoded.length, i + chunkSize));
          }
          expect(decoder.close(), data, reason: 'length $length/$chunkSize');
        }
      }
    });

    test('skips whitespace and line breaks', () {
      final decoder = Base64ByteDecoder()
        ..add(ascii.encode(' SGVs\r\nbG8g\tV29y\nbGQ= \n'));
      expect(utf8.decode(decoder.close()), 'Hello World');
    });

    test('accepts the URL-safe alphabet', () {
      final data = Uint8List.fromList([0xFB, 0xFF, 0xBF]);
      final decoder = Base64ByteDecoder()
        ..add(ascii.encode(base64Url.encode(data)));
      expect(decoder.close(), data);
    });

    test('uses an exact expected length without copying', () {
      final decoder = Base64ByteDecoder(11)
        ..add(ascii.encode('SGVsbG8gV29ybGQ='));
      final result = decoder.close();
      expect(result.length, 11);
      expect(result.buffer.lengthInBytes, 11);
    });

    test('grows past a wrong expected length', () {
      final decoder = Base64ByteDecoder(2)
        ..add(ascii.encode('SGVsbG8gV29ybGQ='));
      expect(utf8.decode(decoder.close()), 'Hello World');
    });

    test('rejects invalid characters', () {
      final decoder = Base64ByteDecoder()..add(ascii.encode('SGV*bG8='));
      expect(decoder.close, throwsFormatException);
    });

    test('rejects data after padding', () {
      final decoder = Base64ByteDecoder()..add(ascii.encode('SGU=SGU='));
      expect(decoder.close, throwsFormatException);
    });

    test('rejects truncated data', () {
      final decoder = Base64ByteDecoder()..add(ascii.encode('SGVsb'));
      expect(decoder.close, throwsFormatException);
    });
  });
}
