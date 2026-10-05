import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:indi/src/exceptions.dart';
import 'package:indi/src/protocol/xml_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart' as xml;

import '../support/fixtures.dart';

/// Parses [chunks] and returns the elements and errors produced.
({List<XmlElementNode> elements, List<IndiProtocolException> errors}) parse(
  Iterable<List<int>> chunks, {
  int maxTextLength = 4 * 1024 * 1024,
}) {
  final elements = <XmlElementNode>[];
  final errors = <IndiProtocolException>[];
  final parser = IndiXmlParser(
    onElement: elements.add,
    onError: errors.add,
    maxTextLength: maxTextLength,
  );
  chunks.forEach(parser.add);
  parser.close();
  return (elements: elements, errors: errors);
}

List<XmlElementNode> parseString(String input) {
  final result = parse([utf8.encode(input)]);
  expect(result.errors, isEmpty);
  return result.elements;
}

/// A comparable description of an element tree.
Object? describe(XmlElementNode node) => {
      'name': node.name,
      'attributes': node.attributes,
      'text': node.text,
      'binary': node.binary?.toList(),
      'children': node.children.map(describe).toList(),
    };

void main() {
  group('IndiXmlParser', () {
    test('parses attributes, text and children', () {
      final elements = parseString(
        "<newNumberVector device='Mount' name=\"COORD\">\n"
        "  <oneNumber name='RA'> 5.5 </oneNumber>\n"
        '</newNumberVector>',
      );
      expect(elements, hasLength(1));
      final vector = elements.single;
      expect(vector.name, 'newNumberVector');
      expect(vector.attributes, {'device': 'Mount', 'name': 'COORD'});
      expect(vector.children.single.name, 'oneNumber');
      expect(vector.children.single.attributes, {'name': 'RA'});
      expect(vector.children.single.text, '5.5');
    });

    test('parses a stream of top-level elements without a root', () {
      final elements = parseString(sessionXml);
      expect(elements.map((e) => e.name), [
        'defSwitchVector',
        'defTextVector',
        'defNumberVector',
        'message',
        'defLightVector',
        'defBLOBVector',
        'setNumberVector',
        'setBLOBVector',
        'delProperty',
        'pingRequest',
      ]);
    });

    test('decodes entities in attributes and text', () {
      final element = parseString(
        "<message message='a &lt;b&gt; &amp; &apos;c&apos; &quot;d&quot; "
        "&#65;&#x42; &unknown;'>x &amp;&#x263A;</message>",
      ).single;
      expect(element.attributes['message'], 'a <b> & \'c\' "d" AB &unknown;');
      expect(element.text, 'x &☺');
    });

    test('decodes multi-byte UTF-8 text', () {
      final element =
          parseString("<message message='Température 5 °C ✓'/>").single;
      expect(element.attributes['message'], 'Température 5 °C ✓');
    });

    test(
        'skips comments, processing instructions, declarations and '
        'keeps CDATA as text', () {
      final elements = parseString(
        "<?xml version='1.0'?>\n<!DOCTYPE indi>\n<!-- a -- comment -->\n"
        "<oneText name='t'><!-- inside -->a<![CDATA[<b>&amp;]]]>c</oneText>",
      );
      expect(elements.single.text, 'a<b>&amp;]c');
    });

    test('decodes oneBLOB content as base64 bytes', () {
      final elements = parseString(sessionXml);
      final blob =
          elements.firstWhere((e) => e.name == 'setBLOBVector').children.single;
      expect(blob.binary, utf8.encode('Hello World'));
      expect(blob.text, isEmpty);
    });

    test('a self-closing oneBLOB has no data', () {
      final blob = parseString(
        "<setBLOBVector device='d' name='n'>"
        "<oneBLOB name='b' size='0' format='.fits'/></setBLOBVector>",
      ).single.children.single;
      expect(blob.binary, isNull);
    });

    test('decodes large BLOBs without an enclen hint', () {
      final data = Uint8List.fromList(
        List.generate(300000, (i) => (i * 31 + 7) & 0xFF),
      );
      final encoded = base64Encode(data);
      final element = parseString(
        "<setBLOBVector device='d' name='n'>"
        "<oneBLOB name='b' format='.bin'>$encoded</oneBLOB></setBLOBVector>",
      ).single;
      expect(element.children.single.binary, data);
    });

    test('produces the same result for any chunking of the input', () {
      final bytes = utf8.encode(sessionXml);
      final expected = parse([bytes]).elements.map(describe).toList();

      final singleBytes = parse([
        for (final b in bytes) [b]
      ]);
      expect(singleBytes.errors, isEmpty);
      expect(singleBytes.elements.map(describe).toList(), expected);

      final random = Random(1);
      for (var round = 0; round < 50; round++) {
        final chunks = <List<int>>[];
        var start = 0;
        while (start < bytes.length) {
          final end = min(bytes.length, start + 1 + random.nextInt(64));
          chunks.add(Uint8List.sublistView(bytes, start, end));
          start = end;
        }
        final result = parse(chunks);
        expect(result.errors, isEmpty);
        expect(result.elements.map(describe).toList(), expected);
      }
    });

    test('accepts chunks that are plain List<int>', () {
      final result = parse([utf8.encode('<pingRequest uid="1"/>').toList()]);
      expect(result.elements.single.attributes['uid'], '1');
    });

    test('matches package:xml on the session fixture', () {
      final document = xml.XmlDocument.parse('<root>$sessionXml</root>');
      final ours = parseString(sessionXml);
      final theirs = document.rootElement.childElements.toList();
      expect(ours, hasLength(theirs.length));
      for (var i = 0; i < ours.length; i++) {
        expect(ours[i].name, theirs[i].name.local);
        expect(ours[i].attributes, {
          for (final a in theirs[i].attributes) a.name.local: a.value,
        });
        final ourChildren = ours[i].children;
        final theirChildren = theirs[i].childElements.toList();
        expect(ourChildren.map((c) => c.name),
            theirChildren.map((c) => c.name.local));
        for (var c = 0; c < ourChildren.length; c++) {
          if (ourChildren[c].binary != null) continue;
          expect(ourChildren[c].text, theirChildren[c].innerText.trim());
        }
      }
    });

    group('error recovery', () {
      test('reports a mismatched closing tag and continues', () {
        final result = parse([
          utf8.encode(
            "<setTextVector device='d' name='n'><oneText name='t'>x</oops>"
            "</setTextVector>\n<pingRequest uid='7'/>",
          ),
        ]);
        expect(result.errors, isNotEmpty);
        expect(result.errors.first.message, contains('</oops>'));
        expect(result.elements.last.name, 'pingRequest');
        expect(result.elements.last.attributes['uid'], '7');
      });

      test('reports unquoted attributes and continues', () {
        final result = parse([
          utf8.encode("<message device=d/>\n<pingReply uid='1'/>"),
        ]);
        expect(result.errors, hasLength(1));
        expect(result.elements.single.name, 'pingReply');
      });

      test('reports bad base64 and continues', () {
        final result = parse([
          utf8.encode(
            "<setBLOBVector device='d' name='n'><oneBLOB name='b'>@@@@"
            "</oneBLOB></setBLOBVector><pingReply uid='1'/>",
          ),
        ]);
        expect(result.errors.single.message, contains('base64'));
        expect(result.elements.single.name, 'pingReply');
      });

      test('limits the text size of non-binary elements', () {
        final result = parse(
          [
            utf8.encode(
              "<oneText name='t'>${'x' * 100}</oneText><pingReply uid='1'/>",
            ),
          ],
          maxTextLength: 10,
        );
        expect(result.errors.single.message, contains('exceeds'));
        expect(result.elements.single.name, 'pingReply');
      });

      test('reports input that ends inside an element', () {
        final result = parse([utf8.encode("<setTextVector device='d'>")]);
        expect(result.elements, isEmpty);
        expect(result.errors.single.message, contains('ended'));
      });

      test('stops skipping a broken element at the next command', () {
        final result = parse([
          utf8.encode(
            "<setTextVector device='d' name='n'><oneText name='t'>x</oops>"
            "<pingRequest uid='1'/><message message='m'/>",
          ),
        ]);
        expect(result.errors, hasLength(1));
        expect(result.elements.map((e) => e.name), ['pingRequest', 'message']);
      });

      test('reports an unterminated command and parses the next one', () {
        final result = parse([
          utf8.encode(
            "<setNumberVector device='d' name='n'><oneNumber name='x'>1"
            "<setTextVector device='d' name='t'><oneText name='a'>b</oneText>"
            '</setTextVector>',
          ),
        ]);
        expect(result.errors.single.message, contains('not closed'));
        expect(result.elements.single.name, 'setTextVector');
        expect(result.elements.single.attributes['name'], 't');
        expect(result.elements.single.children.single.text, 'b');
      });

      test('reports a stray closing tag', () {
        final result = parse([utf8.encode("</a><pingReply uid='1'/>")]);
        expect(result.errors, hasLength(1));
        expect(result.elements, hasLength(1));
      });
    });
  });
}
