import 'dart:math' as math;

final RegExp _specifier = RegExp(
  r'%([-+ 0#]*)(\d+)?(?:\.(\d*))?(?:hh|h|ll|l|L|q|j|z|t)?([diouxXeEfFgGm])',
);

/// Formats [value] the way INDI drivers expect it to be displayed, using the
/// `format` attribute of a number element.
///
/// Supports the printf conversions drivers use (`%f`, `%e`, `%g`, `%d`,
/// `%x`, … with flags, width and precision) and the INDI sexagesimal
/// conversion `%<w>.<f>m`, where `<f>` selects the resolution:
///
/// | `<f>` | output        |
/// |-------|---------------|
/// | 3     | `-dd:mm`      |
/// | 5     | `-dd:mm.m`    |
/// | 6     | `-dd:mm:ss`   |
/// | 8     | `-dd:mm:ss.s` |
/// | 9     | `-dd:mm:ss.ss`|
///
/// For example `%010.6m` formats `-23.5` as `' -23:30:00'`. Text around the
/// conversion is kept. If [format] has no valid conversion, [value] is
/// formatted with `%g`.
///
/// {@category Protocol}
String formatIndiNumber(double value, String format) {
  final match = _findSpecifier(format);
  if (match == null) return _formatSpec(value, '', null, null, 'g');
  final prefix = format.substring(0, match.start).replaceAll('%%', '%');
  final suffix = format.substring(match.end).replaceAll('%%', '%');
  final flags = match.group(1)!;
  final width = match.group(2) == null ? null : int.parse(match.group(2)!);
  final precisionText = match.group(3);
  final precision = precisionText == null
      ? null
      : (precisionText.isEmpty ? 0 : int.parse(precisionText));
  final conversion = match.group(4)!;
  final body = conversion == 'm'
      ? formatSexagesimal(
          value,
          width: (width ?? 0) - (precision ?? 0),
          fractionDigits: precision ?? 0,
        )
      : _formatSpec(value, flags, width, precision, conversion);
  return '$prefix$body$suffix';
}

RegExpMatch? _findSpecifier(String format) {
  for (final match in _specifier.allMatches(format)) {
    // Skip a match whose '%' is escaped by a preceding '%'.
    var percents = 0;
    for (var i = match.start - 1; i >= 0 && format[i] == '%'; i--) {
      percents++;
    }
    if (percents.isEven) return match;
  }
  return null;
}

/// Formats [value] in sexagesimal notation, as libindi's `fs_sexa` does.
///
/// [width] is the minimum width of the whole (degrees or hours) part.
/// [fractionDigits] selects the resolution, with the same meaning as `<f>`
/// in a `%<w>.<f>m` format: 3 → `:mm`, 5 → `:mm.m`, 6 → `:mm:ss`,
/// 8 → `:mm:ss.s` and 9 → `:mm:ss.ss`. Other values use `:mm`.
///
/// {@category Protocol}
String formatSexagesimal(
  double value, {
  int width = 0,
  int fractionDigits = 6,
}) {
  final fractionBase = switch (fractionDigits) {
    9 => 360000,
    8 => 36000,
    6 => 3600,
    5 => 600,
    _ => 60,
  };
  if (value.isNaN) return 'nan'.padLeft(width);
  if (value.isInfinite) return (value < 0 ? '-inf' : 'inf').padLeft(width);
  final negative = value < 0;
  final total = (value.abs() * fractionBase + 0.5).floor();
  final whole = total ~/ fractionBase;
  final fraction = total % fractionBase;
  final out = StringBuffer();
  if (negative && whole == 0) {
    out.write('-0'.padLeft(math.max(width, 2)));
  } else {
    out.write((negative ? -whole : whole).toString().padLeft(width));
  }
  String two(int n) => n.toString().padLeft(2, '0');
  final perMinute = fractionBase ~/ 60;
  switch (fractionBase) {
    case 60:
      out.write(':${two(fraction)}');
    case 600:
      out.write(':${two(fraction ~/ 10)}.${fraction % 10}');
    case 3600:
      out.write(':${two(fraction ~/ perMinute)}:${two(fraction % perMinute)}');
    case 36000:
      final seconds = fraction % perMinute;
      out.write(':${two(fraction ~/ perMinute)}:${two(seconds ~/ 10)}'
          '.${seconds % 10}');
    case 360000:
      final seconds = fraction % perMinute;
      out.write(':${two(fraction ~/ perMinute)}:${two(seconds ~/ 100)}'
          '.${two(seconds % 100)}');
  }
  return out.toString();
}

/// Parses a number sent by an INDI driver or typed by a user.
///
/// Accepts plain decimal numbers (`12.5`, `-1e-3`), `nan` and `inf`, and
/// sexagesimal values with `:`, `;` or spaces as separators (`12:30:00`,
/// `-12 30`, `5;30;15.5`). Returns `null` if [text] is not a number.
///
/// {@category Protocol}
double? parseIndiNumber(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  final decimal = double.tryParse(trimmed);
  if (decimal != null) return decimal;
  switch (trimmed.toLowerCase()) {
    case 'nan' || '+nan' || '-nan':
      return double.nan;
    case 'inf' || '+inf' || 'infinity' || '+infinity':
      return double.infinity;
    case '-inf' || '-infinity':
      return double.negativeInfinity;
  }
  return parseSexagesimal(trimmed);
}

final RegExp _sexagesimalSeparator = RegExp(r'[:;\s]+');

/// Parses a sexagesimal value such as `-12:30:45.5`, `12 30` or `5;30`.
///
/// Up to three components (whole, minutes, seconds) are accepted; the sign
/// applies to the whole value. Returns `null` if [text] is not valid.
///
/// {@category Protocol}
double? parseSexagesimal(String text) {
  var rest = text.trim();
  var negative = false;
  if (rest.startsWith('-')) {
    negative = true;
    rest = rest.substring(1);
  } else if (rest.startsWith('+')) {
    rest = rest.substring(1);
  }
  final parts =
      rest.split(_sexagesimalSeparator).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty || parts.length > 3) return null;
  var result = 0.0;
  var divisor = 1.0;
  for (final part in parts) {
    if (part.startsWith('-') || part.startsWith('+')) return null;
    final component = double.tryParse(part);
    if (component == null || !component.isFinite) return null;
    result += component / divisor;
    divisor *= 60;
  }
  return negative ? -result : result;
}

String _formatSpec(
  double value,
  String flags,
  int? width,
  int? precision,
  String conversion,
) {
  final leftAlign = flags.contains('-');
  final zeroPad = flags.contains('0') && !leftAlign;
  final alternate = flags.contains('#');
  final upper = conversion == conversion.toUpperCase() &&
      conversion != 'd' &&
      conversion != 'i';

  String sign = '';
  String digits;
  if (value.isNaN || value.isInfinite) {
    if (value.isInfinite && value < 0) sign = '-';
    digits = value.isNaN ? 'nan' : 'inf';
    if (upper) digits = digits.toUpperCase();
    final signed = _applySign(sign, flags);
    return _pad('$signed$digits', width, leftAlign: leftAlign);
  }

  switch (conversion) {
    case 'd' || 'i' || 'u':
      final n = value.round();
      sign = n < 0 ? '-' : '';
      digits = n.abs().toString();
      if (precision != null) digits = digits.padLeft(precision, '0');
    case 'o':
      final n = value.round();
      sign = n < 0 ? '-' : '';
      digits = n.abs().toRadixString(8);
    case 'x' || 'X':
      final n = value.round();
      sign = n < 0 ? '-' : '';
      digits = n.abs().toRadixString(16);
      if (conversion == 'X') digits = digits.toUpperCase();
    case 'f' || 'F':
      sign = _isNegative(value) ? '-' : '';
      digits = value.abs().toStringAsFixed(precision ?? 6);
      if (alternate && !digits.contains('.')) digits = '$digits.';
    case 'e' || 'E':
      sign = _isNegative(value) ? '-' : '';
      digits = _exponential(value.abs(), precision ?? 6, upper: upper);
    default: // g, G
      sign = _isNegative(value) ? '-' : '';
      digits = _general(value.abs(), precision ?? 6, alternate, upper: upper);
  }

  final signed = _applySign(sign, flags);
  if (zeroPad && width != null) {
    final padding = width - signed.length - digits.length;
    if (padding > 0) digits = '${'0' * padding}$digits';
  }
  return _pad('$signed$digits', width, leftAlign: leftAlign);
}

bool _isNegative(double value) => value < 0 || (value == 0 && value.isNegative);

String _applySign(String sign, String flags) {
  if (sign.isNotEmpty) return sign;
  if (flags.contains('+')) return '+';
  if (flags.contains(' ')) return ' ';
  return '';
}

String _pad(String text, int? width, {required bool leftAlign}) {
  if (width == null || text.length >= width) return text;
  return leftAlign ? text.padRight(width) : text.padLeft(width);
}

/// C-style `%e`: mantissa with [precision] decimals and an exponent of at
/// least two digits.
String _exponential(double value, int precision, {required bool upper}) {
  final raw = value.toStringAsExponential(precision);
  final e = raw.indexOf('e');
  final mantissa = raw.substring(0, e);
  final exponent = int.parse(raw.substring(e + 1));
  final exponentText = exponent.abs().toString().padLeft(2, '0');
  final result = '${mantissa}e${exponent < 0 ? '-' : '+'}$exponentText';
  return upper ? result.toUpperCase() : result;
}

/// C-style `%g`: the shorter of `%e` and `%f` for the given number of
/// significant digits, without trailing zeros unless [alternate] is set.
String _general(
  double value,
  int precision,
  bool alternate, {
  required bool upper,
}) {
  final significant = precision == 0 ? 1 : precision;
  var exponent = 0;
  if (value != 0) {
    final raw = value.toStringAsExponential(significant - 1);
    exponent = int.parse(raw.substring(raw.indexOf('e') + 1));
  }
  String result;
  if (exponent < -4 || exponent >= significant) {
    result = _exponential(value, significant - 1, upper: upper);
    if (!alternate) {
      final e = result.indexOf(upper ? 'E' : 'e');
      result = _stripZeros(result.substring(0, e)) + result.substring(e);
    }
  } else {
    result = value.toStringAsFixed(significant - 1 - exponent);
    if (!alternate) result = _stripZeros(result);
  }
  return result;
}

String _stripZeros(String number) {
  if (!number.contains('.')) return number;
  var end = number.length;
  while (number[end - 1] == '0') {
    end--;
  }
  if (number[end - 1] == '.') end--;
  return number.substring(0, end);
}
