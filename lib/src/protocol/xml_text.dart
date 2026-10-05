/// Replaces XML entity references in [input] with the characters they stand
/// for.
///
/// Handles the five predefined entities and decimal or hexadecimal character
/// references. Unknown or malformed references are kept as they are.
String decodeXmlEntities(String input) {
  var ampersand = input.indexOf('&');
  if (ampersand < 0) return input;
  final out = StringBuffer();
  var start = 0;
  while (ampersand >= 0) {
    final semicolon = input.indexOf(';', ampersand + 1);
    if (semicolon < 0) break;
    final replacement = _entity(input.substring(ampersand + 1, semicolon));
    if (replacement != null) {
      out
        ..write(input.substring(start, ampersand))
        ..write(replacement);
      start = semicolon + 1;
      ampersand = input.indexOf('&', start);
    } else {
      ampersand = input.indexOf('&', ampersand + 1);
    }
  }
  out.write(input.substring(start));
  return out.toString();
}

String? _entity(String name) {
  switch (name) {
    case 'lt':
      return '<';
    case 'gt':
      return '>';
    case 'amp':
      return '&';
    case 'apos':
      return "'";
    case 'quot':
      return '"';
  }
  if (name.length < 2 || name.codeUnitAt(0) != 0x23 /* # */) return null;
  final hex = name[1] == 'x' || name[1] == 'X';
  final digits = hex ? name.substring(2) : name.substring(1);
  final code = int.tryParse(digits, radix: hex ? 16 : 10);
  if (code == null || code < 0 || code > 0x10FFFF) return null;
  return String.fromCharCode(code);
}

/// Escapes [input] for use inside XML element content.
String escapeXmlText(String input) => _escape(input, attribute: false);

/// Escapes [input] for use inside a single- or double-quoted XML attribute.
String escapeXmlAttribute(String input) => _escape(input, attribute: true);

String _escape(String input, {required bool attribute}) {
  StringBuffer? out;
  var start = 0;
  for (var i = 0; i < input.length; i++) {
    final String replacement;
    switch (input.codeUnitAt(i)) {
      case 0x26: // &
        replacement = '&amp;';
      case 0x3C: // <
        replacement = '&lt;';
      case 0x3E: // >
        replacement = '&gt;';
      case 0x27 when attribute: // '
        replacement = '&apos;';
      case 0x22 when attribute: // "
        replacement = '&quot;';
      default:
        continue;
    }
    (out ??= StringBuffer())
      ..write(input.substring(start, i))
      ..write(replacement);
    start = i + 1;
  }
  if (out == null) return input;
  out.write(input.substring(start));
  return out.toString();
}
