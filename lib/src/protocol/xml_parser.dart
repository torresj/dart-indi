import 'dart:convert';
import 'dart:typed_data';

import '../exceptions.dart';
import 'base64_decoder.dart';
import 'xml_text.dart';

/// A parsed XML element.
final class XmlElementNode {
  /// Creates an element called [name] with [attributes].
  XmlElementNode(this.name, this.attributes);

  /// The element name.
  final String name;

  /// The element attributes, with entities already decoded.
  final Map<String, String> attributes;

  /// The child elements, in document order.
  final List<XmlElementNode> children = [];

  /// The text content with entities decoded and surrounding whitespace
  /// removed. Empty for binary elements.
  String text = '';

  /// The decoded content of a binary (base64) element, or `null` if the
  /// element is not binary.
  Uint8List? binary;

  @override
  String toString() => '<$name ${attributes.entries.map((e) => '${e.key}='
      '"${e.value}"').join(' ')}>';
}

enum _State {
  text,
  binaryText,
  lessThan,
  startName,
  inTag,
  attributeName,
  afterAttributeName,
  beforeAttributeValue,
  attributeValue,
  selfClosing,
  endName,
  afterEndName,
  bang,
  comment,
  cdata,
  declaration,
  processingInstruction,
}

/// Incremental parser for the INDI wire format: an endless sequence of
/// top-level XML elements without an enclosing document.
///
/// Feed raw bytes with [add], in chunks of any size; every complete
/// top-level element is passed to `onElement`. The content of binary
/// elements (`oneBLOB`) is base64-decoded while it streams in.
///
/// Problems are reported to `onError` and the parser resynchronizes on the
/// next top-level element, so one malformed message never stops the stream.
final class IndiXmlParser {
  /// Creates a parser that reports top-level elements to [onElement] and
  /// problems to [onError].
  ///
  /// [maxTextLength] limits the text and attribute size of non-binary
  /// elements, protecting against unbounded memory use on garbage input.
  IndiXmlParser({
    required void Function(XmlElementNode element) onElement,
    required void Function(IndiProtocolException error) onError,
    bool Function(String name)? isBinaryElement,
    this.maxTextLength = 4 * 1024 * 1024,
  })  : _onElement = onElement,
        _onError = onError,
        _isBinaryElement = isBinaryElement ?? _isOneBlob;

  /// The maximum number of bytes of text or attribute data per element.
  final int maxTextLength;

  final void Function(XmlElementNode) _onElement;
  final void Function(IndiProtocolException) _onError;
  final bool Function(String) _isBinaryElement;

  static bool _isOneBlob(String name) => name == 'oneBLOB';

  final List<XmlElementNode> _stack = [];
  _State _state = _State.text;

  final BytesBuilder _text = BytesBuilder();
  final BytesBuilder _token = BytesBuilder();
  String _tagName = '';
  String _attributeName = '';
  Map<String, String> _attributes = {};
  int _quote = 0;
  int _markupMatch = 0;
  Base64ByteDecoder? _binary;

  /// While recovering from an error: the name of the top-level element whose
  /// remaining content is skipped, and how many nested elements with the
  /// same name are open.
  String? _skipName;
  int _skipNesting = 0;

  /// Feeds the next chunk of bytes to the parser.
  void add(List<int> input) {
    final chunk = input is Uint8List ? input : Uint8List.fromList(input);
    var i = 0;
    final length = chunk.length;
    while (i < length) {
      switch (_state) {
        case _State.text:
          final lt = _indexOfLessThan(chunk, i);
          if (_stack.isNotEmpty && _skipName == null && lt > i) {
            if (_text.length + (lt - i) > maxTextLength) {
              _fail('Element text exceeds $maxTextLength bytes');
            } else {
              _text.add(Uint8List.sublistView(chunk, i, lt));
            }
          }
          if (lt == length) return;
          i = lt + 1;
          _state = _State.lessThan;
        case _State.binaryText:
          final lt = _indexOfLessThan(chunk, i);
          _binary!.add(chunk, i, lt);
          if (lt == length) return;
          i = lt + 1;
          _state = _State.lessThan;
        case _State.lessThan:
          final c = chunk[i++];
          if (c == 0x2F /* / */) {
            _token.clear();
            _state = _State.endName;
          } else if (c == 0x21 /* ! */) {
            _token.clear();
            _state = _State.bang;
          } else if (c == 0x3F /* ? */) {
            _markupMatch = 0;
            _state = _State.processingInstruction;
          } else if (_isNameChar(c)) {
            _token
              ..clear()
              ..addByte(c);
            _state = _State.startName;
          } else {
            _fail('Unexpected character after "<"');
          }
        case _State.startName:
          final c = chunk[i];
          if (_isNameChar(c)) {
            _token.addByte(c);
            i++;
          } else {
            _tagName = _takeToken();
            _attributes = {};
            _state = _State.inTag;
          }
        case _State.inTag:
          final c = chunk[i++];
          if (_isWhitespace(c)) continue;
          if (c == 0x3E /* > */) {
            _openElement(selfClosing: false);
          } else if (c == 0x2F /* / */) {
            _state = _State.selfClosing;
          } else if (_isNameChar(c)) {
            _token
              ..clear()
              ..addByte(c);
            _state = _State.attributeName;
          } else {
            _fail('Unexpected character in <$_tagName>');
          }
        case _State.attributeName:
          final c = chunk[i];
          if (_isNameChar(c)) {
            _token.addByte(c);
            i++;
          } else {
            _attributeName = _takeToken();
            _state = _State.afterAttributeName;
          }
        case _State.afterAttributeName:
          final c = chunk[i++];
          if (_isWhitespace(c)) continue;
          if (c == 0x3D /* = */) {
            _state = _State.beforeAttributeValue;
          } else {
            _fail('Attribute "$_attributeName" of <$_tagName> has no value');
          }
        case _State.beforeAttributeValue:
          final c = chunk[i++];
          if (_isWhitespace(c)) continue;
          if (c == 0x22 /* " */ || c == 0x27 /* ' */) {
            _quote = c;
            _token.clear();
            _state = _State.attributeValue;
          } else {
            _fail('Attribute "$_attributeName" of <$_tagName> is not quoted');
          }
        case _State.attributeValue:
          final end = _indexOf(chunk, _quote, i);
          if (_token.length + (end - i) > maxTextLength) {
            _fail('Attribute "$_attributeName" exceeds $maxTextLength bytes');
            continue;
          }
          _token.add(Uint8List.sublistView(chunk, i, end));
          if (end == length) return;
          i = end + 1;
          _attributes[_attributeName] = decodeXmlEntities(_takeToken());
          _state = _State.inTag;
        case _State.selfClosing:
          final c = chunk[i++];
          if (c == 0x3E /* > */) {
            _openElement(selfClosing: true);
          } else {
            _fail('Expected ">" after "/" in <$_tagName>');
          }
        case _State.endName:
          final c = chunk[i];
          if (_isNameChar(c)) {
            _token.addByte(c);
            i++;
          } else {
            _tagName = _takeToken();
            _state = _State.afterEndName;
          }
        case _State.afterEndName:
          final c = chunk[i++];
          if (_isWhitespace(c)) continue;
          if (c == 0x3E /* > */) {
            _closeElement(_tagName);
          } else {
            _fail('Unexpected character in </$_tagName>');
          }
        case _State.bang:
          // Collect enough characters to tell a comment, a CDATA section and
          // a declaration apart.
          _token.addByte(chunk[i++]);
          final prefix = _token.toBytes();
          if (_startsWith(prefix, _commentStart)) {
            _token.clear();
            _markupMatch = 0;
            _state = _State.comment;
          } else if (_startsWith(prefix, _cdataStart)) {
            _token.clear();
            _markupMatch = 0;
            _state = _State.cdata;
          } else if (!_startsWith(_commentStart, prefix) &&
              !_startsWith(_cdataStart, prefix)) {
            _token.clear();
            _state = prefix.last == 0x3E /* > */
                ? _contentState()
                : _State.declaration;
          }
        case _State.comment:
          // Look for "-->".
          final c = chunk[i++];
          if (c == 0x2D /* - */) {
            _markupMatch++;
          } else if (c == 0x3E /* > */ && _markupMatch >= 2) {
            _state = _contentState();
          } else {
            _markupMatch = 0;
          }
        case _State.cdata:
          // Look for "]]>", keeping everything else as text.
          final c = chunk[i++];
          if (c == 0x5D /* ] */) {
            _markupMatch++;
          } else if (c == 0x3E /* > */ && _markupMatch >= 2) {
            for (var k = 0; k < _markupMatch - 2; k++) {
              _addCdataByte(0x5D);
            }
            _state = _contentState();
          } else {
            for (var k = 0; k < _markupMatch; k++) {
              _addCdataByte(0x5D);
            }
            _markupMatch = 0;
            _addCdataByte(c);
          }
        case _State.declaration:
          if (chunk[i++] == 0x3E /* > */) _state = _contentState();
        case _State.processingInstruction:
          final c = chunk[i++];
          if (c == 0x3E /* > */ && _markupMatch == 1) {
            _state = _contentState();
          } else {
            _markupMatch = c == 0x3F /* ? */ ? 1 : 0;
          }
      }
    }
  }

  /// Signals the end of the input. Reports an error if the input stopped in
  /// the middle of an element, and resets the parser.
  void close() {
    if (_stack.isNotEmpty || _state != _State.text) {
      final where = _stack.isNotEmpty ? ' inside <${_stack.first.name}>' : '';
      _fail('Input ended in the middle of an element$where');
    }
  }

  /// Names of the top-level INDI commands, which never appear nested.
  static const Set<String> _commandNames = {
    'defTextVector',
    'defNumberVector',
    'defSwitchVector',
    'defLightVector',
    'defBLOBVector',
    'setTextVector',
    'setNumberVector',
    'setSwitchVector',
    'setLightVector',
    'setBLOBVector',
    'newTextVector',
    'newNumberVector',
    'newSwitchVector',
    'newBLOBVector',
    'getProperties',
    'enableBLOB',
    'delProperty',
    'message',
    'pingRequest',
    'pingReply',
  };

  static const List<int> _escapedAmpersand = [0x26, 0x61, 0x6D, 0x70, 0x3B];
  static const List<int> _commentStart = [0x2D, 0x2D]; // --
  static const List<int> _cdataStart = [
    0x5B, 0x43, 0x44, 0x41, 0x54, 0x41, 0x5B, // [CDATA[
  ];

  void _addCdataByte(int byte) {
    if (_binary != null) {
      _binary!.add([byte]);
    } else if (_stack.isNotEmpty) {
      // Entities are decoded when the element ends, so escape '&' to keep
      // CDATA content literal.
      if (byte == 0x26 /* & */) {
        _text.add(_escapedAmpersand);
      } else {
        _text.addByte(byte);
      }
    }
  }

  _State _contentState() => _binary != null ? _State.binaryText : _State.text;

  void _openElement({required bool selfClosing}) {
    final isCommand = _commandNames.contains(_tagName);
    if (_skipName != null) {
      if (isCommand && _tagName != _skipName) {
        // INDI commands never nest, so a new one means the broken element
        // is over even though it was never closed.
        _skipName = null;
      } else {
        if (!selfClosing && _tagName == _skipName) _skipNesting++;
        _attributes = {};
        _state = _State.text;
        return;
      }
    } else if (isCommand && _stack.isNotEmpty) {
      final unclosed = _stack.first.name;
      final attributes = _attributes;
      _fail('<$unclosed> was not closed before <$_tagName>');
      _skipName = null;
      _attributes = attributes;
    }
    final element = XmlElementNode(_tagName, _attributes);
    _attributes = {};
    if (_stack.isNotEmpty) {
      // Text before a child element is not meaningful in INDI.
      _text.clear();
    }
    _stack.add(element);
    if (selfClosing) {
      _closeElement(element.name);
      return;
    }
    if (_isBinaryElement(element.name)) {
      _binary = Base64ByteDecoder(_expectedBinaryLength(element.attributes));
      _state = _State.binaryText;
    } else {
      _state = _State.text;
    }
  }

  void _closeElement(String name) {
    if (_skipName != null) {
      if (name == _skipName && _skipNesting-- == 0) _skipName = null;
      _state = _State.text;
      return;
    }
    if (_stack.isEmpty) {
      _state = _State.text;
      _onError(IndiProtocolException('Unexpected closing tag </$name>'));
      return;
    }
    final element = _stack.last;
    if (element.name != name) {
      _fail('Closing tag </$name> does not match <${element.name}>');
      return;
    }
    final binary = _binary;
    if (binary != null) {
      _binary = null;
      try {
        element.binary = binary.close();
      } on FormatException catch (e) {
        _fail('Bad base64 data in <${element.name}>: ${e.message}');
        return;
      }
    } else if (_text.isNotEmpty) {
      element.text = decodeXmlEntities(
        utf8.decode(_text.takeBytes(), allowMalformed: true).trim(),
      );
    }
    _stack.removeLast();
    _state = _State.text;
    if (_stack.isEmpty) {
      _onElement(element);
    } else {
      _stack.last.children.add(element);
    }
  }

  /// Reports [message] and drops everything parsed for the current
  /// top-level element. The rest of that element is skipped silently, so
  /// parsing restarts cleanly at the next one.
  void _fail(String message) {
    final root = _stack.isNotEmpty ? _stack.first : null;
    final context = root == null ? '' : ' (in $root)';
    if (root != null) {
      _skipName = root.name;
      _skipNesting = 0;
    }
    _stack.clear();
    _text.clear();
    _token.clear();
    _binary = null;
    _attributes = {};
    _state = _State.text;
    _onError(IndiProtocolException('$message$context'));
  }

  String _takeToken() => utf8.decode(_token.takeBytes(), allowMalformed: true);

  static int _expectedBinaryLength(Map<String, String> attributes) {
    final encodedLength = int.tryParse(attributes['enclen'] ?? '');
    if (encodedLength != null && encodedLength > 0) {
      return encodedLength * 3 ~/ 4;
    }
    final format = attributes['format'] ?? '';
    final size = int.tryParse(attributes['size'] ?? '');
    // For compressed formats `size` is the uncompressed size.
    if (size != null && size > 0 && !format.endsWith('.z')) return size;
    return 0;
  }

  static int _indexOfLessThan(List<int> chunk, int start) =>
      _indexOf(chunk, 0x3C, start);

  static int _indexOf(List<int> chunk, int byte, int start) {
    final length = chunk.length;
    for (var i = start; i < length; i++) {
      if (chunk[i] == byte) return i;
    }
    return length;
  }

  static bool _startsWith(List<int> bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return true;
  }

  static bool _isWhitespace(int c) =>
      c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09;

  static bool _isNameChar(int c) =>
      !_isWhitespace(c) &&
      c != 0x3E /* > */ &&
      c != 0x2F /* / */ &&
      c != 0x3D /* = */ &&
      c != 0x3C /* < */ &&
      c != 0x22 /* " */ &&
      c != 0x27 /* ' */;
}
