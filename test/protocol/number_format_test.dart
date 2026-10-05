import 'package:indi/protocol.dart';
import 'package:test/test.dart';

void main() {
  group('formatIndiNumber', () {
    // Expected values match the output of C printf / libindi numberFormat.
    const cases = <(String, double, String)>[
      ('%g', 0, '0'),
      ('%g', 100000, '100000'),
      ('%g', 1000000, '1e+06'),
      ('%g', 0.0001, '0.0001'),
      ('%g', 0.00001, '1e-05'),
      ('%g', 3.14159265, '3.14159'),
      ('%.3g', 1234.5, '1.23e+03'),
      ('%#g', 1.5, '1.50000'),
      ('%G', 1e-10, '1E-10'),
      ('%f', 1.5, '1.500000'),
      ('%.2f', 2.345, '2.35'),
      ('%.0f', 2.6, '3'),
      ('%8.3f', -1.5, '  -1.500'),
      ('%-8.2f|', 1.5, '1.50    |'),
      ('%08.2f', -1.5, '-0001.50'),
      ('%+.1f', 2, '+2.0'),
      ('% .1f', 2, ' 2.0'),
      ('%e', 12345.678, '1.234568e+04'),
      ('%.2E', 0.000123, '1.23E-04'),
      ('%d', 42.4, '42'),
      ('%5d', -7, '   -7'),
      ('%05d', 42, '00042'),
      ('%.3d', 7, '007'),
      ('%x', 255, 'ff'),
      ('%X', 255, 'FF'),
      ('%o', 8, '10'),
      ('%ld', 3, '3'),
      ('%6.2lf', 3.14159, '  3.14'),
      ('%.1f%%', 50, '50.0%'),
      ('Temp: %.1f C', 21.26, 'Temp: 21.3 C'),
      ('%f', double.nan, 'nan'),
      ('%5.1f', double.negativeInfinity, ' -inf'),
      ('no conversion', 2.5, '2.5'),
      // Sexagesimal, as libindi fs_sexa.
      ('%010.6m', 5.5916666666666668, '   5:35:30'),
      ('%010.6m', -23.5, ' -23:30:00'),
      ('%9.6m', 1 / 60 + 2 / 3600, '  0:01:02'),
      ('%7.3m', -123.75, '-123:45'),
      ('%6.3m', -0.5, ' -0:30'),
      ('%8.5m', 12.505, ' 12:30.3'),
      ('%11.8m', 1.0001, '  1:00:00.4'),
      ('%12.9m', -45.123456, '-45:07:24.44'),
      ('%.6m', 359.99999, '360:00:00'),
      ('%m', 1.5, '1:30'),
    ];

    for (final (format, value, expected) in cases) {
      test('$format of $value', () {
        expect(formatIndiNumber(value, format), expected);
      });
    }
  });

  group('parseIndiNumber', () {
    test('parses decimal numbers', () {
      expect(parseIndiNumber(' 12.5 '), 12.5);
      expect(parseIndiNumber('-1e-3'), -0.001);
      expect(parseIndiNumber('+3'), 3);
    });

    test('parses special values', () {
      expect(parseIndiNumber('nan'), isNaN);
      expect(parseIndiNumber('-NaN'), isNaN);
      expect(parseIndiNumber('inf'), double.infinity);
      expect(parseIndiNumber('-inf'), double.negativeInfinity);
    });

    test('parses sexagesimal values', () {
      expect(parseIndiNumber('12:30:00'), 12.5);
      expect(parseIndiNumber('-12 30 00'), -12.5);
      expect(parseIndiNumber('5;30'), 5.5);
      expect(parseIndiNumber('-0:30'), -0.5);
      expect(parseIndiNumber('+1:00:36'), closeTo(1.01, 1e-12));
      expect(parseIndiNumber('10:30.5'), closeTo(10 + 30.5 / 60, 1e-12));
    });

    test('rejects invalid values', () {
      expect(parseIndiNumber(''), isNull);
      expect(parseIndiNumber('   '), isNull);
      expect(parseIndiNumber('abc'), isNull);
      expect(parseIndiNumber('1:2:3:4'), isNull);
      expect(parseIndiNumber('1:-2'), isNull);
      expect(parseIndiNumber('-'), isNull);
    });
  });

  group('formatSexagesimal', () {
    test('round-trips through parseSexagesimal', () {
      for (final value in [0.0, 1.25, -1.25, 23.999, -89.5, 180.0]) {
        final text = formatSexagesimal(value, fractionDigits: 9);
        expect(parseSexagesimal(text), closeTo(value, 1 / 360000));
      }
    });
  });
}
