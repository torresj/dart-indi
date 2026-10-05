import 'dart:convert';
import 'dart:typed_data';

import 'package:indi/protocol.dart';
import 'package:test/test.dart';

IndiCommand decodeOne(List<int> bytes) {
  final commands = <IndiCommand>[];
  IndiStreamDecoder(
    onCommand: commands.add,
    onError: (e) => fail('Unexpected error: $e'),
  )
    ..add(bytes)
    ..close();
  return commands.single;
}

final _time = DateTime.utc(2026, 10, 4, 21, 30, 15);

final List<IndiCommand> samples = [
  const GetProperties(),
  const GetProperties(device: "Bob's <Mount>", name: 'COORD'),
  const EnableBlob(mode: BlobMode.only, device: 'CCD', name: 'CCD1'),
  const EnableBlob(mode: BlobMode.never, device: 'CCD'),
  DelProperty(device: 'd', name: 'p', timestamp: _time, message: 'bye'),
  const DelProperty(device: 'd'),
  MessageCommand(device: 'd', timestamp: _time, message: 'a & b < c "q"'),
  const MessageCommand(message: 'generic'),
  const PingRequest(uid: '1'),
  const PingReply(uid: '1'),
  DefTextVector(
    device: 'd',
    name: 'T',
    label: 'Text',
    group: 'G',
    state: PropertyState.ok,
    perm: PropertyPermission.readOnly,
    timeout: 0.5,
    timestamp: _time,
    message: 'm',
    elements: const [
      DefText(name: 'a', label: 'A', value: 'multi\nline & <xml>'),
      DefText(name: 'b'),
    ],
  ),
  const DefNumberVector(
    device: 'd',
    name: 'N',
    state: PropertyState.busy,
    elements: [
      DefNumber(
        name: 'x',
        format: '%010.6m',
        min: -90,
        max: 90,
        step: 0.25,
        value: -12.345678901234567,
      ),
      DefNumber(name: 'y', value: 1e-12),
      DefNumber(name: 'z', value: double.nan),
    ],
  ),
  const DefSwitchVector(
    device: 'd',
    name: 'S',
    rule: SwitchRule.atMostOne,
    perm: PropertyPermission.writeOnly,
    elements: [
      DefSwitch(name: 'on', state: SwitchState.on),
      DefSwitch(name: 'off', label: 'Off', state: SwitchState.off),
    ],
  ),
  const DefLightVector(
    device: 'd',
    name: 'L',
    state: PropertyState.alert,
    elements: [DefLight(name: 'l', state: PropertyState.busy)],
  ),
  const DefBlobVector(
    device: 'd',
    name: 'B',
    elements: [DefBlob(name: 'b', label: 'Blob')],
  ),
  SetTextVector(
    device: 'd',
    name: 'T',
    state: PropertyState.ok,
    timestamp: _time,
    elements: const [OneText(name: 'a', value: "it's")],
  ),
  const SetNumberVector(
    device: 'd',
    name: 'N',
    timeout: 3,
    elements: [
      OneNumber(name: 'x', value: 1.5, min: 0, max: 10, step: 0.5),
      OneNumber(name: 'y', value: -0.001),
    ],
  ),
  const SetSwitchVector(
    device: 'd',
    name: 'S',
    elements: [OneSwitch(name: 'on', state: SwitchState.off)],
  ),
  const SetLightVector(
    device: 'd',
    name: 'L',
    message: 'warning',
    elements: [OneLight(name: 'l', state: PropertyState.alert)],
  ),
  SetBlobVector(
    device: 'd',
    name: 'B',
    state: PropertyState.ok,
    elements: [
      OneBlob(
        name: 'b',
        format: '.fits.z',
        data: Uint8List.fromList(List.generate(1000, (i) => i % 251)),
        size: 5000,
      ),
      OneBlob(name: 'empty', format: '.fits', data: Uint8List(0)),
    ],
  ),
  NewTextVector(
    device: 'd',
    name: 'T',
    timestamp: _time,
    elements: const [OneText(name: 'a', value: '')],
  ),
  const NewNumberVector(
    device: 'd',
    name: 'N',
    elements: [OneNumber(name: 'x', value: 123456789.123)],
  ),
  const NewSwitchVector(
    device: 'd',
    name: 'S',
    elements: [OneSwitch(name: 'on', state: SwitchState.on)],
  ),
  NewBlobVector(
    device: 'd',
    name: 'B',
    elements: [
      OneBlob(name: 'b', format: '.txt', data: utf8.encode('hello')),
    ],
  ),
];

void main() {
  group('encodeIndiCommand', () {
    for (final command in samples) {
      test('round-trips ${command.runtimeType} $command', () {
        final xml = encodeIndiCommand(command);
        expect(decodeOne(utf8.encode(xml)), command);
      });
    }

    test('produces the XML libindi expects', () {
      expect(
        encodeIndiCommand(const NewNumberVector(
          device: 'Telescope Simulator',
          name: 'EQUATORIAL_EOD_COORD',
          elements: [
            OneNumber(name: 'RA', value: 5.59),
            OneNumber(name: 'DEC', value: -5),
          ],
        )),
        "<newNumberVector device='Telescope Simulator' "
        "name='EQUATORIAL_EOD_COORD'>\n"
        "  <oneNumber name='RA'>5.59</oneNumber>\n"
        "  <oneNumber name='DEC'>-5</oneNumber>\n"
        '</newNumberVector>\n',
      );
      expect(
        encodeIndiCommand(const GetProperties()),
        "<getProperties version='1.7'/>\n",
      );
      expect(
        encodeIndiCommand(
          const EnableBlob(mode: BlobMode.also, device: 'CCD Simulator'),
        ),
        "<enableBLOB device='CCD Simulator'>Also</enableBLOB>\n",
      );
    });

    test('escapes attributes and text', () {
      final xml = encodeIndiCommand(const NewTextVector(
        device: "a'b\"c",
        name: 'n',
        elements: [OneText(name: 't', value: '<&>')],
      ));
      expect(xml, contains("device='a&apos;b&quot;c'"));
      expect(xml, contains('&lt;&amp;&gt;'));
    });
  });

  group('encodeIndiCommandChunks', () {
    test('splits large BLOBs into chunks that decode to the same command', () {
      final data = Uint8List.fromList(
        List.generate(500000, (i) => (i * 7) & 0xFF),
      );
      final command = NewBlobVector(
        device: 'd',
        name: 'B',
        elements: [OneBlob(name: 'b', format: '.bin', data: data)],
      );
      final chunks = encodeIndiCommandChunks(command).toList();
      expect(chunks.length, greaterThan(5));
      for (final chunk in chunks) {
        expect(chunk.length, lessThan(70 * 1024));
      }
      final bytes = [for (final chunk in chunks) ...chunk];
      expect(utf8.decode(bytes), encodeIndiCommand(command));
      expect(decodeOne(bytes), command);
    });
  });

  group('IndiEncoder', () {
    test('encodes a stream of commands', () async {
      final bytes = await Stream.fromIterable(samples)
          .transform(const IndiEncoder())
          .expand((chunk) => chunk)
          .toList();
      final decoded =
          await Stream.value(bytes).transform(const IndiDecoder()).toList();
      expect(decoded, samples);
    });
  });

  group('formatWireNumber', () {
    test('formats integers without a fraction', () {
      expect(formatWireNumber(10), '10');
      expect(formatWireNumber(-3), '-3');
      expect(formatWireNumber(0), '0');
    });

    test('uses the shortest round-trip representation', () {
      expect(formatWireNumber(5.59), '5.59');
      expect(formatWireNumber(1e-7), '1e-7');
      // The VM prints '...0.0' and JavaScript '...0'; both parse back.
      expect(double.parse(formatWireNumber(1e20)), 1e20);
      expect(double.parse(formatWireNumber(0.1 + 0.2)), 0.1 + 0.2);
    });

    test('formats special values the way C parses them', () {
      expect(formatWireNumber(double.nan), 'nan');
      expect(formatWireNumber(double.infinity), 'inf');
      expect(formatWireNumber(double.negativeInfinity), '-inf');
    });
  });
}
