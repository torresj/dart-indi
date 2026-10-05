import 'package:indi/protocol.dart';
import 'package:test/test.dart';

void main() {
  group('parseIndiTimestamp', () {
    test('parses INDI timestamps as UTC', () {
      final time = parseIndiTimestamp('2026-10-04T21:15:30');
      expect(time, DateTime.utc(2026, 10, 4, 21, 15, 30));
      expect(time!.isUtc, isTrue);
    });

    test('parses fractional seconds', () {
      expect(
        parseIndiTimestamp('2026-10-04T21:15:30.25'),
        DateTime.utc(2026, 10, 4, 21, 15, 30, 250),
      );
      expect(
        parseIndiTimestamp('2026-10-04T21:15:30.1234567'),
        DateTime.utc(2026, 10, 4, 21, 15, 30, 123, 456),
      );
    });

    test('accepts Z and explicit offsets', () {
      expect(
        parseIndiTimestamp('2026-10-04T21:15:30Z'),
        DateTime.utc(2026, 10, 4, 21, 15, 30),
      );
      expect(
        parseIndiTimestamp('2026-10-04T23:15:30+02:00'),
        DateTime.utc(2026, 10, 4, 21, 15, 30),
      );
      expect(
        parseIndiTimestamp('2026-10-04T16:15:30-0500'),
        DateTime.utc(2026, 10, 4, 21, 15, 30),
      );
    });

    test('returns null for missing or invalid values', () {
      expect(parseIndiTimestamp(null), isNull);
      expect(parseIndiTimestamp(''), isNull);
      expect(parseIndiTimestamp('yesterday'), isNull);
      expect(parseIndiTimestamp('2026-10-04 21:15:30'), isNull);
    });
  });

  group('formatIndiTimestamp', () {
    test('formats in UTC without a zone suffix', () {
      expect(
        formatIndiTimestamp(DateTime.utc(2026, 1, 2, 3, 4, 5, 600)),
        '2026-01-02T03:04:05',
      );
    });

    test('converts local times to UTC', () {
      final local = DateTime(2026, 6, 1, 12);
      expect(
        parseIndiTimestamp(formatIndiTimestamp(local)),
        local.toUtc(),
      );
    });
  });
}
