import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:indi/protocol.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

List<IndiCommand> decodeAll(String xml, {List<Object>? errors}) {
  final commands = <IndiCommand>[];
  IndiStreamDecoder(
    onCommand: commands.add,
    onError: errors?.add ?? (e) => fail('Unexpected error: $e'),
  )
    ..add(utf8.encode(xml))
    ..close();
  return commands;
}

void main() {
  group('decoding the session fixture', () {
    late List<IndiCommand> commands;
    setUp(() => commands = decodeAll(sessionXml));

    test('defSwitchVector', () {
      expect(
        commands[0],
        DefSwitchVector(
          device: 'Telescope Simulator',
          name: 'CONNECTION',
          label: 'Connection',
          group: 'Main Control',
          state: PropertyState.idle,
          perm: PropertyPermission.readWrite,
          rule: SwitchRule.oneOfMany,
          timeout: 60,
          timestamp: DateTime.utc(2026, 10, 4, 20, 15, 1),
          elements: const [
            DefSwitch(
                name: 'CONNECT', label: 'Connect', state: SwitchState.off),
            DefSwitch(
              name: 'DISCONNECT',
              label: 'Disconnect',
              state: SwitchState.on,
            ),
          ],
        ),
      );
    });

    test('defTextVector', () {
      final vector = commands[1] as DefTextVector;
      expect(vector.perm, PropertyPermission.readOnly);
      expect(vector.elements.map((e) => e.value), [
        'Telescope Simulator',
        'indi_simulator_telescope',
        '1.0',
        '5',
      ]);
    });

    test('defNumberVector', () {
      final vector = commands[2] as DefNumberVector;
      expect(
          vector.elements.first,
          const DefNumber(
            name: 'RA',
            label: 'RA (hh:mm:ss)',
            format: '%010.6m',
            min: 0,
            max: 24,
            step: 0,
            value: 5.5916666666666668,
          ));
      expect(vector.elements.last.min, -90);
    });

    test('message', () {
      expect(
        commands[3],
        MessageCommand(
          device: 'Telescope Simulator',
          timestamp: DateTime.utc(2026, 10, 4, 20, 15, 2),
          message: "[INFO] Telescope 'simulator' is online & ready. "
              'Temp < 5 °C ',
        ),
      );
    });

    test('defLightVector', () {
      final vector = commands[4] as DefLightVector;
      expect(vector.elements.map((e) => e.state),
          [PropertyState.ok, PropertyState.idle]);
    });

    test('defBLOBVector', () {
      final vector = commands[5] as DefBlobVector;
      expect(vector.perm, PropertyPermission.readOnly);
      expect(
          vector.elements.single, const DefBlob(name: 'CCD1', label: 'Image'));
    });

    test('setNumberVector with sexagesimal values', () {
      final vector = commands[6] as SetNumberVector;
      expect(vector.state, PropertyState.busy);
      expect(vector.elements, const [
        OneNumber(name: 'RA', value: 5.5),
        OneNumber(name: 'DEC', value: -5.25),
      ]);
    });

    test('setBLOBVector', () {
      final blob = (commands[7] as SetBlobVector).elements.single;
      expect(blob.name, 'CCD1');
      expect(blob.format, '.fits');
      expect(blob.size, 11);
      expect(utf8.decode(blob.data), 'Hello World');
    });

    test('delProperty and pingRequest', () {
      expect(
        commands[8],
        DelProperty(
          device: 'Telescope Simulator',
          name: 'STATUS',
          timestamp: DateTime.utc(2026, 10, 4, 20, 15, 6),
        ),
      );
      expect(commands[9], const PingRequest(uid: '42'));
    });
  });

  group('commandFromXml', () {
    test('decodes client commands', () {
      final commands = decodeAll(
        "<getProperties version='1.7' device='Mount'/>"
        "<enableBLOB device='CCD' name='CCD1'> Also </enableBLOB>"
        "<newSwitchVector device='Mount' name='CONNECTION'>"
        "<oneSwitch name='CONNECT'>On</oneSwitch></newSwitchVector>"
        "<newTextVector device='Mount' name='PORT'>"
        "<oneText name='PORT'>/dev/ttyUSB0</oneText></newTextVector>"
        "<newNumberVector device='Mount' name='COORD'>"
        "<oneNumber name='RA'>1e1</oneNumber></newNumberVector>"
        "<newBLOBVector device='Mount' name='FILE'>"
        "<oneBLOB name='F' size='3' format='.bin'>AQID</oneBLOB>"
        '</newBLOBVector>'
        "<pingReply uid='x'/>",
      );
      expect(commands[0], const GetProperties(device: 'Mount'));
      expect(
        commands[1],
        const EnableBlob(mode: BlobMode.also, device: 'CCD', name: 'CCD1'),
      );
      expect(
        commands[2],
        const NewSwitchVector(
          device: 'Mount',
          name: 'CONNECTION',
          elements: [OneSwitch(name: 'CONNECT', state: SwitchState.on)],
        ),
      );
      expect(
          (commands[3] as NewTextVector).elements.single.value, '/dev/ttyUSB0');
      expect((commands[4] as NewNumberVector).elements.single.value, 10);
      expect((commands[5] as NewBlobVector).elements.single.data, [1, 2, 3]);
      expect(commands[6], const PingReply(uid: 'x'));
    });

    test('decodes min, max and step updates in oneNumber', () {
      final vector = decodeAll(
        "<setNumberVector device='F' name='ABS'>"
        "<oneNumber name='POS' min='0' max='5000' step='10'>100</oneNumber>"
        '</setNumberVector>',
      ).single as SetNumberVector;
      expect(
        vector.elements.single,
        const OneNumber(name: 'POS', value: 100, min: 0, max: 5000, step: 10),
      );
    });

    test('keeps optional set attributes null when absent', () {
      final vector = decodeAll(
        "<setSwitchVector device='d' name='n'>"
        "<oneSwitch name='a'>on</oneSwitch></setSwitchVector>",
      ).single as SetSwitchVector;
      expect(vector.state, isNull);
      expect(vector.timeout, isNull);
      expect(vector.timestamp, isNull);
      expect(vector.message, isNull);
      expect(vector.elements.single.state, SwitchState.on);
    });

    test('falls back to defaults for invalid optional attributes', () {
      final vector = decodeAll(
        "<defSwitchVector device='d' name='n' state='Weird' perm='x'>"
        "<defSwitch name='a'>maybe</defSwitch><defSwitch>no name</defSwitch>"
        "<other name='b'/></defSwitchVector>",
      ).single as DefSwitchVector;
      expect(vector.state, PropertyState.idle);
      expect(vector.perm, PropertyPermission.readWrite);
      expect(vector.rule, SwitchRule.anyOfMany);
      expect(vector.elements.single,
          const DefSwitch(name: 'a', state: SwitchState.off));
    });

    test('a number that cannot be parsed becomes NaN', () {
      final vector = decodeAll(
        "<setNumberVector device='d' name='n'>"
        "<oneNumber name='a'>abc</oneNumber></setNumberVector>",
      ).single as SetNumberVector;
      expect(vector.elements.single.value, isNaN);
    });

    test('a message without device is generic', () {
      final message = decodeAll("<message device='' message='hi'/>").single
          as MessageCommand;
      expect(message.device, isNull);
      expect(message.message, 'hi');
    });

    test('reports missing required attributes and continues', () {
      final errors = <Object>[];
      final commands = decodeAll(
        "<setTextVector name='n'/><delProperty/><enableBLOB device='d'>"
        "Sometimes</enableBLOB><pingReply uid='1'/>",
        errors: errors,
      );
      expect(errors, hasLength(3));
      expect(errors.first.toString(), contains('"device"'));
      expect(commands, [const PingReply(uid: '1')]);
    });

    test('keeps unknown commands for forward compatibility', () {
      expect(
        decodeAll("<futureThing a='1'/>").single,
        const UnknownCommand(tag: 'futureThing', attributes: {'a': '1'}),
      );
    });
  });

  group('IndiDecoder', () {
    test('transforms a byte stream and keeps going after errors', () async {
      final controller = StreamController<List<int>>();
      final events = <Object>[];
      final done = Completer<void>();
      controller.stream.transform(const IndiDecoder()).listen(
            events.add,
            onError: events.add,
            onDone: done.complete,
          );
      final bytes = utf8.encode(
        "<pingRequest uid='1'/><delProperty/>\n<pingRequest uid='2'/>",
      );
      for (var i = 0; i < bytes.length; i += 7) {
        controller.add(Uint8List.sublistView(
          bytes,
          i,
          i + 7 > bytes.length ? bytes.length : i + 7,
        ));
      }
      await controller.close();
      await done.future;
      expect(events, hasLength(3));
      expect(events[0], const PingRequest(uid: '1'));
      expect(events[1], isA<IndiProtocolException>());
      expect(events[2], const PingRequest(uid: '2'));
    });
  });
}
