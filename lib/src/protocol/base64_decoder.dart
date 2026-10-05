import 'dart:typed_data';

/// Incrementally decodes base64 text, given as ASCII bytes, into bytes.
///
/// INDI sends BLOBs as base64 with line breaks, and a single image can be
/// tens of megabytes. Decoding the bytes as they arrive avoids building huge
/// intermediate strings. Whitespace is skipped, and both the standard and the
/// URL-safe alphabets are accepted.
final class Base64ByteDecoder {
  /// Creates a decoder. When the decoded length is known in advance, pass it
  /// as [expectedLength] so the output buffer is allocated once.
  Base64ByteDecoder([int expectedLength = 0])
      : _buffer = Uint8List(expectedLength > 0 ? expectedLength : 1024);

  static final Int8List _table = _buildTable();

  Uint8List _buffer;
  int _length = 0;
  int _accumulator = 0;
  int _pending = 0;
  int _padding = 0;
  bool _invalid = false;

  static Int8List _buildTable() {
    // -1: invalid, -2: whitespace, -3: padding.
    final table = Int8List(256)..fillRange(0, 256, -1);
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    for (var i = 0; i < alphabet.length; i++) {
      table[alphabet.codeUnitAt(i)] = i;
    }
    table[0x2D] = 62; // '-'
    table[0x5F] = 63; // '_'
    for (final whitespace in const [0x09, 0x0A, 0x0D, 0x20]) {
      table[whitespace] = -2;
    }
    table[0x3D] = -3; // '='
    return table;
  }

  /// Adds the base64 characters in `bytes[start..end)`.
  void add(List<int> bytes, [int start = 0, int? end]) {
    final stop = end ?? bytes.length;
    final table = _table;
    var accumulator = _accumulator;
    var pending = _pending;
    for (var i = start; i < stop; i++) {
      final value = table[bytes[i] & 0xFF];
      if (value >= 0) {
        if (_padding > 0) {
          _invalid = true;
          continue;
        }
        accumulator = (accumulator << 6) | value;
        if (++pending == 4) {
          _ensureCapacity(3);
          _buffer[_length++] = (accumulator >> 16) & 0xFF;
          _buffer[_length++] = (accumulator >> 8) & 0xFF;
          _buffer[_length++] = accumulator & 0xFF;
          accumulator = 0;
          pending = 0;
        }
      } else if (value == -3) {
        _padding++;
      } else if (value == -1) {
        _invalid = true;
      }
    }
    _accumulator = accumulator;
    _pending = pending;
  }

  /// Finishes decoding and returns the decoded bytes.
  ///
  /// Throws a [FormatException] if the input was not valid base64.
  Uint8List close() {
    if (_invalid) {
      throw const FormatException('Invalid character in base64 data');
    }
    switch (_pending) {
      case 0:
        break;
      case 2:
        _ensureCapacity(1);
        _buffer[_length++] = (_accumulator >> 4) & 0xFF;
      case 3:
        _ensureCapacity(2);
        _buffer[_length++] = (_accumulator >> 10) & 0xFF;
        _buffer[_length++] = (_accumulator >> 2) & 0xFF;
      default:
        throw const FormatException('Truncated base64 data');
    }
    if (_length == _buffer.length) return _buffer;
    // Copy when the buffer is much larger than the data, so the unused part
    // can be garbage collected.
    if (_length < _buffer.length * 3 ~/ 4) {
      return Uint8List.fromList(Uint8List.sublistView(_buffer, 0, _length));
    }
    return Uint8List.sublistView(_buffer, 0, _length);
  }

  void _ensureCapacity(int extra) {
    if (_length + extra <= _buffer.length) return;
    var capacity = _buffer.length * 2;
    while (capacity < _length + extra) {
      capacity *= 2;
    }
    _buffer = Uint8List(capacity)..setRange(0, _length, _buffer);
  }
}
