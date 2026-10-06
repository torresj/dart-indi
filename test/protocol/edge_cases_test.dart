import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:indi/protocol.dart';
import 'package:indi/src/protocol/base64_decoder.dart';
import 'package:indi/src/protocol/xml_parser.dart';
import 'package:indi/src/util/equality.dart';
import 'package:test/test.dart';

({List<XmlElementNode> elements, List<IndiProtocolException> errors}) parse(
  String input,
) {
  final elements = <XmlElementNode>[];
  final errors = <IndiProtocolException>[];
  IndiXmlParser(onElement: elements.add, onError: errors.add)
    ..add(utf8.encode(input))
    ..close();
  return (elements: elements, errors: errors);
}

void main() {
  group('parser errors', () {
    const next = "<pingReply uid='ok'/>";
    final cases = {
      'an unexpected character after "<"': '< foo/>',
      'an unexpected character in a tag': "<message device='d' %/>",
      'an attribute without a value': '<message device/>',
      'a "/" not followed by ">"': '<message /x>',
      'an unexpected character in a closing tag': "<a></a x='1'>",
    };
    for (final MapEntry(key: name, value: input) in cases.entries) {
      test('reports $name and continues', () {
        final result = parse('$input$next');
        expect(result.errors, hasLength(1), reason: input);
        expect(result.elements.last.attributes['uid'], 'ok');
      });
    }

    test('limits attribute values', () {
      final elements = <XmlElementNode>[];
      final errors = <IndiProtocolException>[];
      IndiXmlParser(
        onElement: elements.add,
        onError: errors.add,
        maxTextLength: 8,
      )
        ..add(utf8.encode("<message message='${'x' * 20}'/>$next"))
        ..close();
      expect(errors.single.message, contains('exceeds'));
      expect(elements.single.name, 'pingReply');
    });

    test('skips nested elements with the same name while recovering', () {
      final result = parse(
        "<setTextVector device='d' name='n'><oneText name='t'>x</bad>"
        '<setTextVector><oneText/></setTextVector>'
        '</setTextVector>$next',
      );
      expect(result.errors, hasLength(1));
      expect(result.elements.single.name, 'pingReply');
    });

    test('an empty declaration is ignored', () {
      final result = parse('<!>$next');
      expect(result.errors, isEmpty);
      expect(result.elements.single.name, 'pingReply');
    });
  });

  group('CDATA', () {
    test('keeps "]" characters that do not end the section', () {
      final element = parse('<oneText name="t"><![CDATA[a]b]]c]]]]></oneText>')
          .elements
          .single;
      expect(element.text, 'a]b]]c]]');
    });

    test('is decoded as base64 inside a BLOB', () {
      final element = parse(
        "<setBLOBVector device='d' name='n'><oneBLOB name='b'>"
        '<![CDATA[SGVs]]>bG8=</oneBLOB></setBLOBVector>',
      ).elements.single;
      expect(utf8.decode(element.children.single.binary!), 'Hello');
    });
  });

  test('the base64 decoder grows several times', () {
    final data = Uint8List.fromList(List.generate(100000, (i) => i & 0xFF));
    final decoder = Base64ByteDecoder(1)..add(ascii.encode(base64Encode(data)));
    expect(decoder.close(), data);
  });

  test('IndiDecoder forwards stream errors', () async {
    final controller = StreamController<List<int>>();
    final errors = <Object>[];
    final done = controller.stream
        .transform(const IndiDecoder())
        .handleError(errors.add)
        .drain<void>();
    controller.addError(StateError('socket'));
    await controller.close();
    await done;
    expect(errors.single, isA<StateError>());
  });

  test('UnknownCommand is encoded as an empty element', () {
    expect(
      encodeIndiCommand(
        const UnknownCommand(tag: 'future', attributes: {'a': '1'}),
      ),
      "<future a='1'/>\n",
    );
  });

  group('number formats', () {
    test('ignores an escaped % before the conversion', () {
      expect(formatIndiNumber(5, '100%% at %.1f'), '100% at 5.0');
      expect(formatIndiNumber(5, '%%%.1f'), '%5.0');
    });

    test('uses upper case for special values with upper case conversions', () {
      expect(formatIndiNumber(double.nan, '%F'), 'NAN');
      expect(formatIndiNumber(double.infinity, '%E'), 'INF');
    });

    test('the # flag keeps the decimal point', () {
      expect(formatIndiNumber(3, '%#.0f'), '3.');
    });
  });

  test('deep equality covers maps, byte lists and NaN', () {
    expect(
        deepEquals({
          'a': [1.0, double.nan]
        }, {
          'a': [1.0, double.nan]
        }),
        isTrue);
    expect(deepEquals({'a': 1}, {'b': 1}), isFalse);
    expect(deepEquals({'a': 1}, {'a': 1, 'b': 2}), isFalse);
    expect(
        deepHash({
          'a': [1, 2]
        }),
        deepHash({
          'a': [1, 2]
        }));
    expect(deepHash(Uint8List(5)), 5);
    expect(deepHash(double.nan), 0);
    expect(deepHash('x'), 'x'.hashCode);
  });

  test('commands hash consistently', () {
    const a = GetProperties(device: 'd');
    final b = GetProperties(device: 'd'.toLowerCase());
    expect(identical(a, b), isFalse);
    expect(a.hashCode, b.hashCode);
    expect({a, b}, hasLength(1));
  });
}
