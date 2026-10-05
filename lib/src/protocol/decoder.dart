import 'dart:async';
import 'dart:typed_data';

import '../exceptions.dart';
import '../model/enums.dart';
import 'commands.dart';
import 'number_format.dart';
import 'timestamp.dart';
import 'xml_parser.dart';

/// Incrementally decodes INDI wire bytes into [IndiCommand]s.
///
/// Feed chunks of any size with [add]. Complete commands are passed to
/// `onCommand`; malformed input is reported to `onError` and decoding
/// continues with the next command.
///
/// {@category Protocol}
final class IndiStreamDecoder {
  /// Creates a decoder that reports commands to [onCommand] and problems to
  /// [onError].
  IndiStreamDecoder({
    required void Function(IndiCommand command) onCommand,
    required void Function(IndiProtocolException error) onError,
    int maxTextLength = 4 * 1024 * 1024,
  }) {
    _parser = IndiXmlParser(
      maxTextLength: maxTextLength,
      onError: onError,
      onElement: (element) {
        final IndiCommand command;
        try {
          command = commandFromXml(element);
        } on IndiProtocolException catch (e) {
          onError(e);
          return;
        }
        onCommand(command);
      },
    );
  }

  late final IndiXmlParser _parser;

  /// Feeds the next chunk of bytes.
  void add(List<int> chunk) => _parser.add(chunk);

  /// Signals the end of the input. Reports an error if it stopped in the
  /// middle of a command.
  void close() => _parser.close();
}

/// A [StreamTransformer] that turns INDI wire bytes into [IndiCommand]s.
///
/// Malformed commands are emitted as [IndiProtocolException] errors on the
/// output stream; listen with `cancelOnError: false` (the default) to keep
/// receiving the commands that follow.
///
/// ```dart
/// socket.transform(const IndiDecoder()).listen(print);
/// ```
///
/// {@category Protocol}
final class IndiDecoder extends StreamTransformerBase<List<int>, IndiCommand> {
  /// Creates a decoder.
  const IndiDecoder({this.maxTextLength = 4 * 1024 * 1024});

  /// The maximum size of the text of a non-BLOB element.
  final int maxTextLength;

  @override
  Stream<IndiCommand> bind(Stream<List<int>> stream) =>
      Stream<IndiCommand>.eventTransformed(
        stream,
        (sink) => _DecoderSink(sink, maxTextLength),
      );
}

final class _DecoderSink implements EventSink<List<int>> {
  _DecoderSink(this._out, int maxTextLength) {
    _decoder = IndiStreamDecoder(
      maxTextLength: maxTextLength,
      onCommand: _out.add,
      onError: _out.addError,
    );
  }

  final EventSink<IndiCommand> _out;
  late final IndiStreamDecoder _decoder;

  @override
  void add(List<int> data) => _decoder.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _out.addError(error, stackTrace);

  @override
  void close() {
    _decoder.close();
    _out.close();
  }
}

/// Converts one parsed top-level XML element into an [IndiCommand].
///
/// Throws an [IndiProtocolException] when required attributes are missing
/// or invalid. Optional attributes with invalid values fall back to sensible
/// defaults so that slightly non-conforming drivers still work.
///
/// {@category Protocol}
IndiCommand commandFromXml(XmlElementNode element) {
  final a = _Attributes(element);
  switch (element.name) {
    case 'defTextVector':
      return DefTextVector(
        device: a.required('device'),
        name: a.required('name'),
        label: a.optional('label'),
        group: a.optional('group'),
        state: a.state('state') ?? PropertyState.idle,
        perm: a.perm() ?? PropertyPermission.readWrite,
        timeout: a.number('timeout'),
        timestamp: a.timestamp(),
        message: a.optional('message'),
        elements: [
          for (final child in _children(element, 'defText'))
            DefText(
              name: child.attributes['name']!,
              label: child.attributes['label'],
              value: child.text,
            ),
        ],
      );
    case 'defNumberVector':
      return DefNumberVector(
        device: a.required('device'),
        name: a.required('name'),
        label: a.optional('label'),
        group: a.optional('group'),
        state: a.state('state') ?? PropertyState.idle,
        perm: a.perm() ?? PropertyPermission.readWrite,
        timeout: a.number('timeout'),
        timestamp: a.timestamp(),
        message: a.optional('message'),
        elements: [
          for (final child in _children(element, 'defNumber'))
            DefNumber(
              name: child.attributes['name']!,
              label: child.attributes['label'],
              format: child.attributes['format'] ?? '%g',
              min: _number(child.attributes['min']) ?? 0,
              max: _number(child.attributes['max']) ?? 0,
              step: _number(child.attributes['step']) ?? 0,
              value: _number(child.text) ?? double.nan,
            ),
        ],
      );
    case 'defSwitchVector':
      return DefSwitchVector(
        device: a.required('device'),
        name: a.required('name'),
        label: a.optional('label'),
        group: a.optional('group'),
        state: a.state('state') ?? PropertyState.idle,
        perm: a.perm() ?? PropertyPermission.readWrite,
        rule: SwitchRule.tryParse(a.optional('rule')) ?? SwitchRule.anyOfMany,
        timeout: a.number('timeout'),
        timestamp: a.timestamp(),
        message: a.optional('message'),
        elements: [
          for (final child in _children(element, 'defSwitch'))
            DefSwitch(
              name: child.attributes['name']!,
              label: child.attributes['label'],
              state: SwitchState.tryParse(child.text) ?? SwitchState.off,
            ),
        ],
      );
    case 'defLightVector':
      return DefLightVector(
        device: a.required('device'),
        name: a.required('name'),
        label: a.optional('label'),
        group: a.optional('group'),
        state: a.state('state') ?? PropertyState.idle,
        timestamp: a.timestamp(),
        message: a.optional('message'),
        elements: [
          for (final child in _children(element, 'defLight'))
            DefLight(
              name: child.attributes['name']!,
              label: child.attributes['label'],
              state: PropertyState.tryParse(child.text) ?? PropertyState.idle,
            ),
        ],
      );
    case 'defBLOBVector':
      return DefBlobVector(
        device: a.required('device'),
        name: a.required('name'),
        label: a.optional('label'),
        group: a.optional('group'),
        state: a.state('state') ?? PropertyState.idle,
        perm: a.perm() ?? PropertyPermission.readOnly,
        timeout: a.number('timeout'),
        timestamp: a.timestamp(),
        message: a.optional('message'),
        elements: [
          for (final child in _children(element, 'defBLOB'))
            DefBlob(
              name: child.attributes['name']!,
              label: child.attributes['label'],
            ),
        ],
      );
    case 'setTextVector':
      return SetTextVector(
        device: a.required('device'),
        name: a.required('name'),
        state: a.state('state'),
        timeout: a.number('timeout'),
        timestamp: a.timestamp(),
        message: a.optional('message'),
        elements: _oneTexts(element),
      );
    case 'setNumberVector':
      return SetNumberVector(
        device: a.required('device'),
        name: a.required('name'),
        state: a.state('state'),
        timeout: a.number('timeout'),
        timestamp: a.timestamp(),
        message: a.optional('message'),
        elements: _oneNumbers(element),
      );
    case 'setSwitchVector':
      return SetSwitchVector(
        device: a.required('device'),
        name: a.required('name'),
        state: a.state('state'),
        timeout: a.number('timeout'),
        timestamp: a.timestamp(),
        message: a.optional('message'),
        elements: _oneSwitches(element),
      );
    case 'setLightVector':
      return SetLightVector(
        device: a.required('device'),
        name: a.required('name'),
        state: a.state('state'),
        timestamp: a.timestamp(),
        message: a.optional('message'),
        elements: [
          for (final child in _children(element, 'oneLight'))
            OneLight(
              name: child.attributes['name']!,
              state: PropertyState.tryParse(child.text) ?? PropertyState.idle,
            ),
        ],
      );
    case 'setBLOBVector':
      return SetBlobVector(
        device: a.required('device'),
        name: a.required('name'),
        state: a.state('state'),
        timeout: a.number('timeout'),
        timestamp: a.timestamp(),
        message: a.optional('message'),
        elements: _oneBlobs(element),
      );
    case 'newTextVector':
      return NewTextVector(
        device: a.required('device'),
        name: a.required('name'),
        timestamp: a.timestamp(),
        elements: _oneTexts(element),
      );
    case 'newNumberVector':
      return NewNumberVector(
        device: a.required('device'),
        name: a.required('name'),
        timestamp: a.timestamp(),
        elements: _oneNumbers(element),
      );
    case 'newSwitchVector':
      return NewSwitchVector(
        device: a.required('device'),
        name: a.required('name'),
        timestamp: a.timestamp(),
        elements: _oneSwitches(element),
      );
    case 'newBLOBVector':
      return NewBlobVector(
        device: a.required('device'),
        name: a.required('name'),
        timestamp: a.timestamp(),
        elements: _oneBlobs(element),
      );
    case 'getProperties':
      return GetProperties(
        version: a.optional('version') ?? indiProtocolVersion,
        device: a.nonEmpty('device'),
        name: a.nonEmpty('name'),
      );
    case 'enableBLOB':
      final mode = BlobMode.tryParse(element.text);
      if (mode == null) {
        throw IndiProtocolException(
          'enableBLOB with invalid mode "${element.text}"',
        );
      }
      return EnableBlob(
        mode: mode,
        device: a.required('device'),
        name: a.nonEmpty('name'),
      );
    case 'delProperty':
      return DelProperty(
        device: a.required('device'),
        name: a.nonEmpty('name'),
        timestamp: a.timestamp(),
        message: a.optional('message'),
      );
    case 'message':
      return MessageCommand(
        device: a.nonEmpty('device'),
        timestamp: a.timestamp(),
        message: a.optional('message') ?? '',
      );
    case 'pingRequest':
      return PingRequest(uid: a.optional('uid') ?? '');
    case 'pingReply':
      return PingReply(uid: a.optional('uid') ?? '');
    default:
      return UnknownCommand(
        tag: element.name,
        attributes: Map.unmodifiable(element.attributes),
      );
  }
}

/// Children called [name] that have a `name` attribute.
Iterable<XmlElementNode> _children(XmlElementNode parent, String name) =>
    parent.children.where(
      (child) => child.name == name && child.attributes['name'] != null,
    );

List<OneText> _oneTexts(XmlElementNode element) => [
      for (final child in _children(element, 'oneText'))
        OneText(name: child.attributes['name']!, value: child.text),
    ];

List<OneNumber> _oneNumbers(XmlElementNode element) => [
      for (final child in _children(element, 'oneNumber'))
        OneNumber(
          name: child.attributes['name']!,
          value: _number(child.text) ?? double.nan,
          min: _number(child.attributes['min']),
          max: _number(child.attributes['max']),
          step: _number(child.attributes['step']),
        ),
    ];

List<OneSwitch> _oneSwitches(XmlElementNode element) => [
      for (final child in _children(element, 'oneSwitch'))
        OneSwitch(
          name: child.attributes['name']!,
          state: SwitchState.tryParse(child.text) ?? SwitchState.off,
        ),
    ];

List<OneBlob> _oneBlobs(XmlElementNode element) =>
    [for (final child in _children(element, 'oneBLOB')) _oneBlob(child)];

OneBlob _oneBlob(XmlElementNode child) {
  final data = child.binary ?? Uint8List(0);
  return OneBlob(
    name: child.attributes['name']!,
    format: child.attributes['format'] ?? '',
    data: data,
    size: int.tryParse(child.attributes['size']?.trim() ?? '') ?? data.length,
  );
}

double? _number(String? text) => text == null ? null : parseIndiNumber(text);

final class _Attributes {
  _Attributes(this._element);

  final XmlElementNode _element;

  String required(String name) {
    final value = _element.attributes[name];
    if (value == null || value.isEmpty) {
      throw IndiProtocolException(
        '<${_element.name}> is missing the "$name" attribute',
      );
    }
    return value;
  }

  String? optional(String name) => _element.attributes[name];

  String? nonEmpty(String name) {
    final value = _element.attributes[name];
    return value == null || value.isEmpty ? null : value;
  }

  PropertyState? state(String name) =>
      PropertyState.tryParse(_element.attributes[name]);

  PropertyPermission? perm() =>
      PropertyPermission.tryParse(_element.attributes['perm']);

  double? number(String name) => _number(_element.attributes[name]);

  DateTime? timestamp() => parseIndiTimestamp(_element.attributes['timestamp']);
}
