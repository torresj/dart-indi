final RegExp _timestamp = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?'
  r'(Z|[+-]\d{2}:?\d{2})?$',
);

/// Parses an INDI timestamp such as `2026-10-04T21:15:30.5`.
///
/// INDI timestamps are UTC and normally carry no zone suffix; a `Z` or an
/// explicit offset is also accepted. Returns `null` if [text] is `null`,
/// empty or not a valid timestamp. The result is always in UTC.
///
/// {@category Protocol}
DateTime? parseIndiTimestamp(String? text) {
  if (text == null) return null;
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  final match = _timestamp.firstMatch(trimmed);
  if (match == null) return null;
  int part(int group) => int.parse(match.group(group)!);
  final fraction = match.group(7);
  final microseconds = fraction == null
      ? 0
      : int.parse(fraction.padRight(6, '0').substring(0, 6));
  var result = DateTime.utc(
    part(1),
    part(2),
    part(3),
    part(4),
    part(5),
    part(6),
    0,
    microseconds,
  );
  final zone = match.group(8);
  if (zone != null && zone != 'Z') {
    final digits = zone.replaceAll(':', '');
    final hours = int.parse(digits.substring(1, 3));
    final minutes = int.parse(digits.substring(3, 5));
    final offset = Duration(hours: hours, minutes: minutes);
    result =
        zone.startsWith('-') ? result.add(offset) : result.subtract(offset);
  }
  return result;
}

/// Formats [time] as an INDI timestamp (`YYYY-MM-DDTHH:MM:SS`, in UTC).
///
/// {@category Protocol}
String formatIndiTimestamp(DateTime time) {
  final utc = time.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${utc.year.toString().padLeft(4, '0')}-${two(utc.month)}-'
      '${two(utc.day)}T${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}';
}
