import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'commands.dart';
import 'timestamp.dart';
import 'xml_text.dart';

/// Raw bytes per base64 piece; a multiple of 3, so pieces need no padding.
const int _blobPieceBytes = 48 * 1024;

/// Encodes [command] as an INDI XML string, including a trailing newline.
///
/// BLOB data is base64-encoded inline. For large BLOBs prefer
/// [encodeIndiCommandChunks], which avoids building one huge string.
///
/// {@category Protocol}
String encodeIndiCommand(IndiCommand command) => _pieces(command).join();

/// Encodes [command] as UTF-8 bytes, split into chunks of at most about
/// 64 KiB so large BLOB uploads can be written to a socket progressively.
///
/// {@category Protocol}
Iterable<Uint8List> encodeIndiCommandChunks(IndiCommand command) sync* {
  final pending = StringBuffer();
  for (final piece in _pieces(command)) {
    pending.write(piece);
    if (pending.length >= _blobPieceBytes) {
      yield utf8.encode(pending.toString());
      pending.clear();
    }
  }
  if (pending.isNotEmpty) yield utf8.encode(pending.toString());
}

/// A [StreamTransformer] that encodes [IndiCommand]s into INDI wire bytes.
///
/// {@category Protocol}
final class IndiEncoder extends StreamTransformerBase<IndiCommand, List<int>> {
  /// Creates an encoder.
  const IndiEncoder();

  @override
  Stream<List<int>> bind(Stream<IndiCommand> stream) =>
      stream.expand(encodeIndiCommandChunks);
}

Iterable<String> _pieces(IndiCommand command) sync* {
  switch (command) {
    case DefVector():
      yield* _defVector(command);
    case SetVector():
      yield _open('set${command.type.wireName}Vector', {
        'device': command.device,
        'name': command.name,
        'state': command.state?.wireValue,
        'timeout': _optionalNumber(command.timeout),
        'timestamp': _optionalTimestamp(command.timestamp),
        'message': command.message,
      });
      yield* _oneElements(command.elements);
      yield '</set${command.type.wireName}Vector>\n';
    case NewVector():
      yield _open('new${command.type.wireName}Vector', {
        'device': command.device,
        'name': command.name,
        'timestamp': _optionalTimestamp(command.timestamp),
      });
      yield* _oneElements(command.elements);
      yield '</new${command.type.wireName}Vector>\n';
    case GetProperties():
      yield _empty('getProperties', {
        'version': command.version,
        'device': command.device,
        'name': command.name,
      });
    case EnableBlob():
      yield '${_openTag('enableBLOB', {
            'device': command.device,
            'name': command.name,
          })}${command.mode.wireValue}</enableBLOB>\n';
    case DelProperty():
      yield _empty('delProperty', {
        'device': command.device,
        'name': command.name,
        'timestamp': _optionalTimestamp(command.timestamp),
        'message': command.message,
      });
    case MessageCommand():
      yield _empty('message', {
        'device': command.device,
        'timestamp': _optionalTimestamp(command.timestamp),
        'message': command.message,
      });
    case PingRequest():
      yield _empty('pingRequest', {'uid': command.uid});
    case PingReply():
      yield _empty('pingReply', {'uid': command.uid});
    case UnknownCommand():
      yield _empty(command.tag, command.attributes);
  }
}

Iterable<String> _defVector(DefVector command) sync* {
  final tag = 'def${command.type.wireName}Vector';
  yield _open(tag, {
    'device': command.device,
    'name': command.name,
    'label': command.label,
    'group': command.group,
    'state': command.state.wireValue,
    'perm': switch (command) {
      DefTextVector(:final perm) ||
      DefNumberVector(:final perm) ||
      DefSwitchVector(:final perm) ||
      DefBlobVector(:final perm) =>
        perm.wireValue,
      DefLightVector() => null,
    },
    'rule': command is DefSwitchVector ? command.rule.wireValue : null,
    'timeout': _optionalNumber(command.timeout),
    'timestamp': _optionalTimestamp(command.timestamp),
    'message': command.message,
  });
  for (final element in command.elements) {
    final attributes = {'name': element.name, 'label': element.label};
    switch (element) {
      case DefText():
        yield _textElement('defText', attributes, element.value);
      case DefNumber():
        yield _textElement(
          'defNumber',
          {
            ...attributes,
            'format': element.format,
            'min': formatWireNumber(element.min),
            'max': formatWireNumber(element.max),
            'step': formatWireNumber(element.step),
          },
          formatWireNumber(element.value),
        );
      case DefSwitch():
        yield _textElement('defSwitch', attributes, element.state.wireValue);
      case DefLight():
        yield _textElement('defLight', attributes, element.state.wireValue);
      case DefBlob():
        yield '  ${_empty('defBLOB', attributes)}';
    }
  }
  yield '</$tag>\n';
}

Iterable<String> _oneElements(List<OneElement> elements) sync* {
  for (final element in elements) {
    switch (element) {
      case OneText():
        yield _textElement('oneText', {'name': element.name}, element.value);
      case OneNumber():
        yield _textElement(
          'oneNumber',
          {
            'name': element.name,
            'min': _optionalNumber(element.min),
            'max': _optionalNumber(element.max),
            'step': _optionalNumber(element.step),
          },
          formatWireNumber(element.value),
        );
      case OneSwitch():
        yield _textElement(
          'oneSwitch',
          {'name': element.name},
          element.state.wireValue,
        );
      case OneLight():
        yield _textElement(
          'oneLight',
          {'name': element.name},
          element.state.wireValue,
        );
      case OneBlob():
        final data = element.data;
        final encodedLength = (data.length + 2) ~/ 3 * 4;
        yield '  ${_openTag('oneBLOB', {
              'name': element.name,
              'size': '${element.size}',
              'enclen': '$encodedLength',
              'format': element.format,
            })}';
        for (var start = 0; start < data.length; start += _blobPieceBytes) {
          final end = start + _blobPieceBytes < data.length
              ? start + _blobPieceBytes
              : data.length;
          yield base64Encode(Uint8List.sublistView(data, start, end));
        }
        yield '</oneBLOB>\n';
    }
  }
}

/// Formats [value] for the wire: the shortest text that parses back to the
/// same double, never locale dependent.
///
/// {@category Protocol}
String formatWireNumber(double value) {
  if (value.isNaN) return 'nan';
  if (value.isInfinite) return value > 0 ? 'inf' : '-inf';
  if (value == value.truncateToDouble() && value.abs() < 1e15) {
    return value.toInt().toString();
  }
  return value.toString();
}

String? _optionalNumber(double? value) =>
    value == null ? null : formatWireNumber(value);

String? _optionalTimestamp(DateTime? value) =>
    value == null ? null : formatIndiTimestamp(value);

String _attributes(Map<String, String?> attributes) {
  final out = StringBuffer();
  attributes.forEach((name, value) {
    if (value != null) out.write(" $name='${escapeXmlAttribute(value)}'");
  });
  return out.toString();
}

String _openTag(String tag, Map<String, String?> attributes) =>
    '<$tag${_attributes(attributes)}>';

String _open(String tag, Map<String, String?> attributes) =>
    '${_openTag(tag, attributes)}\n';

String _empty(String tag, Map<String, String?> attributes) =>
    '<$tag${_attributes(attributes)}/>\n';

String _textElement(String tag, Map<String, String?> attributes, String text) =>
    '  ${_openTag(tag, attributes)}${escapeXmlText(text)}</$tag>\n';
