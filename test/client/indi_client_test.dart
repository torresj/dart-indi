import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:indi/indi.dart';
import 'package:indi/testing.dart';
import 'package:test/test.dart';

import '../support/simulators.dart';

void main() {
  late FakeIndiServer server;
  late IndiClient client;

  setUp(() {
    server = FakeIndiServer();
    defineMount(server);
    defineCamera(server);
    client = IndiClient.withTransport(server.transport, options: fastOptions);
  });

  tearDown(() async {
    await client.close();
    await server.close();
  });

  group('connecting', () {
    test('discovers devices and their properties', () async {
      final events = recordEvents(client);
      final (mount, _) = await connectAndSync(client);
      expect(client.isConnected, isTrue);
      expect(client.connectionState, const IndiConnected());

      expect(client.devices.keys, containsAll([mountName, cameraName]));
      expect(mount.isAvailable, isTrue);
      expect(mount.properties.keys, [
        'CONNECTION',
        'DRIVER_INFO',
        'EQUATORIAL_EOD_COORD',
        'TELESCOPE_TRACK_STATE',
        'DEVICE_PORT',
        'STATUS',
      ]);
      expect(mount.groups, ['Main Control', 'General Info', 'Options']);

      await eventually(() => events.whereType<PropertyDefined>().length == 12);
      expect(events.whereType<DeviceAdded>().map((e) => e.device.name),
          [mountName, cameraName]);
      expect(
        events.whereType<ConnectionStateChanged>().map((e) => e.state),
        [const IndiConnecting(), const IndiConnected()],
      );
    });

    test('exposes driver information and interfaces', () async {
      final (mount, _) = await connectAndSync(client);
      expect(mount.driverInfo?.executable, 'indi_simulator_telescope');
      expect(mount.interfaces,
          {DeviceInterface.telescope, DeviceInterface.guider});
      expect(mount.hasInterface(DeviceInterface.ccd), isFalse);
      expect(
        client.devicesWith(DeviceInterface.guider).map((d) => d.name),
        [mountName, cameraName],
      );
      expect(client.devicesWith(DeviceInterface.ccd).single.name, cameraName);
    });

    test('maps definitions to typed snapshots', () async {
      final (mount, _) = await connectAndSync(client);
      final coords = mount.getNumber('EQUATORIAL_EOD_COORD')!;
      expect(coords.label, 'Eq. Coordinates');
      expect(coords.timeout, 60);
      expect(coords.valueOf('RA'), 5.5);
      expect(coords['RA']!.formattedValue, '   5:30:00');
      expect(coords['DEC']!.formattedValue, '  -5:15:00');
      expect(mount.getSwitch('CONNECTION')!.activeElement?.name, 'DISCONNECT');
      expect(mount.getText('DEVICE_PORT')!.valueOf('PORT'), '/dev/ttyUSB0');
      expect(mount.getLight('STATUS')!.permission, PropertyPermission.readOnly);
      expect(mount.getNumber('CONNECTION'), isNull);
      expect(mount.isConnected, isFalse);
    });

    test('a failed first connection throws', () async {
      server.refuseConnections = true;
      await expectLater(
        client.connect(),
        throwsA(isA<IndiConnectionException>()),
      );
      expect(client.connectionState, isA<IndiDisconnected>());
      expect(server.transport.connectAttempts, 1);
    });

    test('retryInitialConnect keeps trying until the server is up', () async {
      final retrying = IndiClient.withTransport(
        server.transport,
        options: const IndiClientOptions(
          retryInitialConnect: true,
          heartbeat: HeartbeatOptions.disabled(),
          reconnect: ReconnectPolicy(
            initialDelay: Duration(milliseconds: 5),
            jitter: 0,
          ),
        ),
      );
      addTearDown(retrying.close);
      server.refuseConnections = true;
      final connected = retrying.connect();
      await eventually(() => server.transport.connectAttempts >= 3);
      server.refuseConnections = false;
      await connected;
      expect(retrying.isConnected, isTrue);
    });

    test('watchDevices limits the session to some devices', () async {
      final watching = IndiClient.withTransport(
        server.transport,
        options: const IndiClientOptions(
          watchDevices: {cameraName},
          heartbeat: HeartbeatOptions.disabled(),
        ),
      );
      addTearDown(watching.close);
      final received = recordReceived(server);
      await watching.connect();
      await watching.waitForDevice(cameraName);
      server.message('hello', device: mountName);
      server.message('hello camera', device: cameraName);
      await eventually(() => watching.messages.isNotEmpty);
      expect(watching.devices.keys, [cameraName]);
      expect(watching.messages.single.text, 'hello camera');
      expect(received.first, const GetProperties(device: cameraName));
    });

    test('commands fail when not connected', () async {
      await client.connect();
      final mount = await client.waitForDevice(mountName);
      await client.disconnect();
      expect(client.devices, isEmpty);
      expect(mount.isAvailable, isFalse);
      expect(mount.isRemoved, isTrue);
      expect(
        () => client.sendCommand(const GetProperties()),
        throwsA(isA<IndiNotConnectedException>()),
      );
    });

    test('can connect again after disconnect', () async {
      await client.connect();
      await client.waitForDevice(mountName);
      await client.disconnect();
      await client.connect();
      final mount = await client.waitForDevice(mountName);
      expect(mount.isAvailable, isTrue);
    });
  });

  group('updates', () {
    setUp(() => connectAndSync(client));

    test('apply set vectors and emit PropertyUpdated', () async {
      final camera = client.device(cameraName)!;
      final updated = camera.eventsOf<PropertyUpdated>().first;
      server.update(const SetNumberVector(
        device: cameraName,
        name: 'CCD_TEMPERATURE',
        state: PropertyState.busy,
        elements: [OneNumber(name: 'CCD_TEMPERATURE_VALUE', value: 12.5)],
      ));
      final event = await updated;
      expect(event.property.state, PropertyState.busy);
      expect(
          (event.property as NumberProperty).valueOf('CCD_TEMPERATURE_VALUE'),
          12.5);
      expect(
          (event.previous as NumberProperty).valueOf('CCD_TEMPERATURE_VALUE'),
          20);
      expect(camera.getNumber('CCD_TEMPERATURE')!.isBusy, isTrue);
    });

    test('watch emits the current value, then each update', () async {
      final camera = client.device(cameraName)!;
      final values = <double>[];
      final subscription = camera
          .watch<NumberProperty>('CCD_TEMPERATURE')
          .listen((p) => values.add(p.valueOf('CCD_TEMPERATURE_VALUE')!));
      addTearDown(subscription.cancel);
      await eventually(() => values.length == 1);
      for (final value in [10.0, 0.0, -10.0]) {
        server.update(SetNumberVector(
          device: cameraName,
          name: 'CCD_TEMPERATURE',
          elements: [OneNumber(name: 'CCD_TEMPERATURE_VALUE', value: value)],
        ));
      }
      await eventually(() => values.length == 4);
      expect(values, [20, 10, 0, -10]);
    });

    test('watch keeps working across deletion and redefinition', () async {
      final camera = client.device(cameraName)!;
      final states = <PropertyState>[];
      final subscription = camera
          .watch<SwitchProperty>('CCD_FRAME_TYPE')
          .listen((p) => states.add(p.state));
      addTearDown(subscription.cancel);
      server.delete(cameraName, 'CCD_FRAME_TYPE');
      await eventually(() => camera['CCD_FRAME_TYPE'] == null);
      server.define(const DefSwitchVector(
        device: cameraName,
        name: 'CCD_FRAME_TYPE',
        state: PropertyState.ok,
        rule: SwitchRule.oneOfMany,
        elements: [DefSwitch(name: 'FRAME_LIGHT', state: SwitchState.on)],
      ));
      await eventually(() => states.length == 2);
      expect(states, [PropertyState.idle, PropertyState.ok]);
    });

    test('updates min, max and step of numbers', () async {
      server.update(const SetNumberVector(
        device: cameraName,
        name: 'CCD_EXPOSURE',
        elements: [
          OneNumber(name: 'CCD_EXPOSURE_VALUE', value: 2, min: 0.1, max: 60),
        ],
      ));
      final camera = client.device(cameraName)!;
      await eventually(
        () =>
            camera.getNumber('CCD_EXPOSURE')!['CCD_EXPOSURE_VALUE']!.max == 60,
      );
      final element = camera.getNumber('CCD_EXPOSURE')!['CCD_EXPOSURE_VALUE']!;
      expect(element.min, 0.1);
      expect(element.step, 1);
      expect(element.value, 2);
    });

    test('ignores updates for unknown properties', () async {
      final events = recordEvents(client);
      server.update(const SetNumberVector(
        device: cameraName,
        name: 'NOPE',
        elements: [OneNumber(name: 'x', value: 1)],
      ));
      server.message('after');
      await eventually(() => events.isNotEmpty);
      expect(events.single, isA<MessageReceived>());
    });

    test('a redefinition replaces the property', () async {
      final camera = client.device(cameraName)!;
      server.define(const DefNumberVector(
        device: cameraName,
        name: 'CCD_TEMPERATURE',
        label: 'Temperature (C)',
        elements: [DefNumber(name: 'CCD_TEMPERATURE_VALUE', value: 5)],
      ));
      await eventually(
        () => camera.getNumber('CCD_TEMPERATURE')!.label == 'Temperature (C)',
      );
    });

    test('a property deleted by the driver is removed', () async {
      final camera = client.device(cameraName)!;
      final removed = camera.eventsOf<PropertyRemoved>().first;
      server.delete(cameraName, 'CCD_TEMPERATURE');
      expect((await removed).property.name, 'CCD_TEMPERATURE');
      expect(camera['CCD_TEMPERATURE'], isNull);
      expect(camera.isAvailable, isTrue);
    });

    test('a device deleted by the driver is removed', () async {
      final camera = client.device(cameraName)!;
      final events = recordEvents(client);
      server.delete(cameraName);
      await eventually(() => events.whereType<DeviceRemoved>().isNotEmpty);
      expect(client.device(cameraName), isNull);
      expect(camera.isAvailable, isFalse);
      expect(events.whereType<PropertyRemoved>(), hasLength(6));

      // Defining it again creates a new device.
      defineCamera(server);
      final again = await client.waitForDevice(cameraName);
      expect(again, isNot(same(camera)));
    });
  });

  group('messages', () {
    setUp(() => connectAndSync(client));

    test('are collected per device and globally', () async {
      final mount = client.device(mountName)!;
      server
        ..message('[WARNING] Mount is near the meridian', device: mountName)
        ..message('server is up');
      await eventually(() => client.messages.length == 2);
      expect(mount.messages.single.level, IndiMessageLevel.warning);
      expect(mount.messages.single.body, 'Mount is near the meridian');
      expect(client.messages.last.device, isNull);
      expect(client.messages.last.level, IndiMessageLevel.info);
    });

    test('include the message attribute of vectors', () async {
      final received = client.eventsOf<MessageReceived>().first;
      server.update(const SetSwitchVector(
        device: mountName,
        name: 'TELESCOPE_TRACK_STATE',
        message: '[INFO] Tracking started',
        elements: [OneSwitch(name: 'TRACK_ON', state: SwitchState.on)],
      ));
      final event = await received;
      expect(event.device?.name, mountName);
      expect(event.message.text, '[INFO] Tracking started');
    });

    test('keep a bounded history', () async {
      final limited = IndiClient.withTransport(
        server.transport,
        options: const IndiClientOptions(
          messageHistory: 3,
          heartbeat: HeartbeatOptions.disabled(),
        ),
      );
      addTearDown(limited.close);
      await limited.connect();
      for (var i = 0; i < 5; i++) {
        server.message('m$i');
      }
      await eventually(
        () => limited.messages.isNotEmpty && limited.messages.last.text == 'm4',
      );
      expect(limited.messages.map((m) => m.text), ['m2', 'm3', 'm4']);
    });
  });

  group('commands', () {
    late IndiDevice mount;
    late IndiDevice camera;
    late List<IndiCommand> received;

    setUp(() async {
      received = recordReceived(server);
      (mount, camera) = await connectAndSync(client);
    });

    test('sendNumbers sends the whole vector and completes on Ok', () async {
      final result = await mount.sendNumbers(
        'EQUATORIAL_EOD_COORD',
        {'RA': 10.5},
      );
      expect(result.state, PropertyState.ok);
      expect(result.valueOf('RA'), 10.5);
      expect(
        received.whereType<NewNumberVector>().single,
        const NewNumberVector(
          device: mountName,
          name: 'EQUATORIAL_EOD_COORD',
          elements: [
            OneNumber(name: 'RA', value: 10.5),
            OneNumber(name: 'DEC', value: -5.25),
          ],
        ),
      );
    });

    test('marks the property Busy until the driver answers', () async {
      final states = <PropertyState>[];
      mount.eventsOf<PropertyUpdated>().listen(
            (e) => states.add(e.property.state),
          );
      await mount.sendNumber('EQUATORIAL_EOD_COORD', 'DEC', 10);
      await eventually(() => states.length == 2);
      expect(states, [PropertyState.busy, PropertyState.ok]);
    });

    test('setSwitch on a OneOfMany property sends all switches', () async {
      final result = await mount.setSwitch('TELESCOPE_TRACK_STATE', 'TRACK_ON');
      expect(result.activeElement?.name, 'TRACK_ON');
      expect(
        received.whereType<NewSwitchVector>().single.elements,
        const [
          OneSwitch(name: 'TRACK_ON', state: SwitchState.on),
          OneSwitch(name: 'TRACK_OFF', state: SwitchState.off),
        ],
      );
    });

    test('connect and disconnect use the CONNECTION property', () async {
      await mount.connect();
      expect(mount.isConnected, isTrue);
      await mount.disconnect();
      expect(mount.isConnected, isFalse);
    });

    test('sendTexts keeps the other elements', () async {
      final result =
          await mount.sendText('DEVICE_PORT', 'PORT', '/dev/ttyACM0');
      expect(result.valueOf('PORT'), '/dev/ttyACM0');
    });

    test('fails with the driver message when the property goes Alert',
        () async {
      server.onNewVector = (command, server) => [
            SetSwitchVector(
              device: command.device,
              name: command.name,
              state: PropertyState.alert,
              message: '[ERROR] Failed to connect to port /dev/ttyUSB0',
              elements: const [],
            ),
          ];
      await expectLater(
        mount.connect(),
        throwsA(isA<IndiPropertyAlertException>()
            .having((e) => e.message, 'message', contains('/dev/ttyUSB0'))
            .having((e) => e.property, 'property', 'CONNECTION')),
      );
    });

    test('afterBusy ignores a stale Ok update', () async {
      final completer = Completer<void>();
      server.onNewVector = (command, server) async {
        // An update that was already on its way, then the real answer.
        server.update(const SetNumberVector(
          device: mountName,
          name: 'EQUATORIAL_EOD_COORD',
          state: PropertyState.ok,
          elements: [OneNumber(name: 'RA', value: 5.6)],
        ));
        await completer.future;
        return [
          const SetNumberVector(
            device: mountName,
            name: 'EQUATORIAL_EOD_COORD',
            state: PropertyState.busy,
            elements: [OneNumber(name: 'RA', value: 8)],
          ),
          const SetNumberVector(
            device: mountName,
            name: 'EQUATORIAL_EOD_COORD',
            state: PropertyState.ok,
            elements: [OneNumber(name: 'RA', value: 10)],
          ),
        ];
      };
      var done = false;
      final slew = mount.sendNumbers(
        'EQUATORIAL_EOD_COORD',
        {'RA': 10, 'DEC': 20},
        completion: CommandCompletion.afterBusy,
      );
      unawaited(slew.then((_) => done = true));
      await eventually(
        () => mount.getNumber('EQUATORIAL_EOD_COORD')!.valueOf('RA') == 5.6,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(done, isFalse);
      completer.complete();
      expect((await slew).valueOf('RA'), 10);
    });

    test('afterBusy completes on an Ok update with the requested values',
        () async {
      final result = await mount.sendNumbers(
        'EQUATORIAL_EOD_COORD',
        {'RA': 1, 'DEC': 2},
        completion: CommandCompletion.afterBusy,
      );
      expect(result.valueOf('DEC'), 2);
    });

    test('completion sent returns as soon as the command is written', () async {
      server.onNewVector = (command, server) => const [];
      final result = await mount.setSwitch(
        'TELESCOPE_TRACK_STATE',
        'TRACK_ON',
        completion: CommandCompletion.sent,
      );
      expect(result.state, PropertyState.busy);
    });

    test('times out when the driver never answers', () async {
      server.onNewVector = (command, server) => const [];
      await expectLater(
        mount.sendNumber(
          'EQUATORIAL_EOD_COORD',
          'RA',
          1,
          timeout: const Duration(milliseconds: 20),
        ),
        throwsA(isA<IndiTimeoutException>()),
      );
    });

    test('fails when the property is deleted while pending', () async {
      server.onNewVector = (command, server) {
        server.delete(command.device, command.name);
        return const [];
      };
      await expectLater(
        mount.sendNumber('EQUATORIAL_EOD_COORD', 'RA', 1),
        throwsA(isA<IndiPropertyRemovedException>()),
      );
    });

    group('validation', () {
      test('rejects unknown properties and elements', () {
        expect(
          () => mount.sendNumber('NOPE', 'RA', 1),
          throwsA(isA<IndiNotFoundException>()),
        );
        expect(
          () => mount.sendNumber('EQUATORIAL_EOD_COORD', 'AZ', 1),
          throwsA(isA<IndiValidationException>()),
        );
        expect(
          () => mount.sendNumber('CONNECTION', 'CONNECT', 1),
          throwsA(isA<IndiValidationException>()),
        );
      });

      test('rejects read-only properties', () {
        expect(
          () => mount.sendText('DRIVER_INFO', 'DRIVER_NAME', 'x'),
          throwsA(isA<IndiPermissionException>()),
        );
      });

      test('rejects numbers out of range', () {
        expect(
          () => mount.sendNumber('EQUATORIAL_EOD_COORD', 'DEC', 91),
          throwsA(isA<IndiValidationException>()),
        );
        expect(
          () => camera.sendNumber('CCD_EXPOSURE', 'CCD_EXPOSURE_VALUE', 0),
          throwsA(isA<IndiValidationException>()),
        );
      });

      test('enforces switch rules', () {
        expect(
          () => mount.setSwitch('TELESCOPE_TRACK_STATE', 'TRACK_ON', on: false),
          throwsA(isA<IndiValidationException>()),
        );
        expect(
          () => camera.sendSwitches(
            'CCD_FRAME_TYPE',
            {'FRAME_DARK': true, 'FRAME_FLAT': true},
          ),
          throwsA(isA<IndiValidationException>()),
        );
      });

      test('can be turned off', () async {
        final lenient = IndiClient.withTransport(
          server.transport,
          options: const IndiClientOptions(
            validateValues: false,
            heartbeat: HeartbeatOptions.disabled(),
          ),
        );
        addTearDown(lenient.close);
        final (lenientMount, _) = await connectAndSync(lenient);
        server.onNewVector = (command, server) => const [];
        await lenientMount.sendNumber(
          'EQUATORIAL_EOD_COORD',
          'DEC',
          91,
          completion: CommandCompletion.sent,
        );
        await eventually(
          () => received.whereType<NewNumberVector>().isNotEmpty,
        );
      });
    });
  });

  group('BLOBs', () {
    final image = Uint8List.fromList(utf8.encode('SIMPLE  =   T'));

    SetBlobVector imageUpdate() => SetBlobVector(
          device: cameraName,
          name: 'CCD1',
          state: PropertyState.ok,
          elements: [OneBlob(name: 'CCD1', format: '.fits', data: image)],
        );

    test('are not received until enabled', () async {
      final (_, camera) = await connectAndSync(client);
      server.update(imageUpdate());
      server.message('sync');
      await eventually(() => client.messages.isNotEmpty);
      expect(camera.getBlob('CCD1')!['CCD1']!.blob, isNull);

      final received = recordReceived(server);
      await camera.setBlobMode(BlobMode.also, property: 'CCD1');
      await eventually(() => received.isNotEmpty);
      expect(
        received.single,
        const EnableBlob(mode: BlobMode.also, device: cameraName, name: 'CCD1'),
      );
      expect(
          client.blobMode(device: cameraName, property: 'CCD1'), BlobMode.also);
      final updated = camera.watch<BlobProperty>('CCD1').skip(1).first;
      server.update(imageUpdate());
      final blob = (await updated)['CCD1']!.blob!;
      expect(blob.bytes, image);
      expect(blob.format, '.fits');
      expect(blob.isCompressed, isFalse);
      expect(blob.decompress(), image);
    });

    test('BLOB modes are sent again when the BLOB property is defined',
        () async {
      await client.setBlobMode(BlobMode.also,
          device: cameraName, property: 'CCD1');
      final received = recordReceived(server);
      await client.connect();
      await client.waitForDevice(cameraName);
      await eventually(() => received.whereType<EnableBlob>().isNotEmpty);
      expect(received.whereType<EnableBlob>().first.name, 'CCD1');
    });

    test('can arrive on a separate connection', () async {
      final split = IndiClient.withTransport(
        server.transport,
        options: const IndiClientOptions(
          separateBlobConnection: true,
          heartbeat: HeartbeatOptions.disabled(),
        ),
      );
      addTearDown(split.close);
      final (_, camera) = await connectAndSync(split);
      await eventually(() => server.connections.length == 2);
      await camera.setBlobMode(BlobMode.also, property: 'CCD1');
      await eventually(
        () => server.connections.any(
          (c) => c.blobMode(cameraName, 'CCD1') == BlobMode.only,
        ),
      );
      expect(
        server.connections
            .where((c) => c.blobMode(cameraName, 'CCD1') == BlobMode.never),
        hasLength(1),
      );
      server.update(imageUpdate());
      await eventually(() => camera.getBlob('CCD1')!['CCD1']!.blob != null);
      expect(camera.getBlob('CCD1')!['CCD1']!.blob!.bytes, image);
    });

    test('uploads with sendBlobs', () async {
      await connectAndSync(client);
      server.define(const DefBlobVector(
        device: cameraName,
        name: 'UPLOAD',
        perm: PropertyPermission.writeOnly,
        elements: [DefBlob(name: 'FILE')],
      ));
      final camera = client.device(cameraName)!;
      await camera.waitForProperty<BlobProperty>('UPLOAD');
      final received = recordReceived(server);
      await camera.sendBlobs('UPLOAD', {
        'FILE': IndiBlob(image, format: '.fits'),
      });
      await eventually(() => received.whereType<NewBlobVector>().isNotEmpty);
      final upload = received.whereType<NewBlobVector>().single;
      expect(upload.elements.single.data, image);
    });
  });

  group('protocol errors', () {
    test('are reported and the session continues', () async {
      await connectAndSync(client);
      final error = client.eventsOf<ProtocolErrorReceived>().first;
      server.connections.single
          .sendRaw(utf8.encode("<setTextVector name='x'></setTextVector>"));
      expect((await error).error.message, contains('device'));
      server.message('still alive');
      await eventually(() => client.messages.isNotEmpty);
      expect(client.isConnected, isTrue);
    });

    test('a set vector of the wrong type is reported', () async {
      await connectAndSync(client);
      final error = client.eventsOf<ProtocolErrorReceived>().first;
      server.connections.single.send(const SetTextVector(
        device: mountName,
        name: 'EQUATORIAL_EOD_COORD',
        elements: [OneText(name: 'RA', value: 'x')],
      ));
      expect((await error).error.message, contains('Number'));
    });
  });

  group('raw access', () {
    test('commands exposes every received command', () async {
      final commands = <IndiCommand>[];
      client.commands.listen(commands.add);
      await connectAndSync(client);
      expect(commands.whereType<DefVector>(), hasLength(12));
    });

    test('ping measures the round trip', () async {
      await client.connect();
      final rtt = await client.ping();
      expect(rtt, lessThan(const Duration(seconds: 1)));
    });

    test('ping times out on servers that do not answer', () async {
      server.answerPings = false;
      await client.connect();
      await expectLater(
        client.ping(timeout: const Duration(milliseconds: 20)),
        throwsA(isA<IndiTimeoutException>()),
      );
    });

    test('answers pings from the server', () async {
      await client.connect();
      final received = recordReceived(server);
      server.connections.single.send(const PingRequest(uid: 'abc'));
      await eventually(() => received.whereType<PingReply>().isNotEmpty);
      expect(
          received.whereType<PingReply>().single, const PingReply(uid: 'abc'));
    });
  });

  group('closing', () {
    test('fails pending waits and closes streams', () async {
      await client.connect();
      final wait = expectLater(
        client.waitForDevice('Nobody'),
        throwsA(isA<IndiClosedException>()),
      );
      final done = client.events.drain<void>();
      await client.close();
      await wait;
      await done;
      expect(client.connectionState, const IndiClosed());
      expect(client.connect, throwsA(isA<IndiClosedException>()));
    });

    test('waitForDevice times out', () async {
      await client.connect();
      await expectLater(
        client.waitForDevice('Nobody',
            timeout: const Duration(milliseconds: 10)),
        throwsA(isA<IndiTimeoutException>()),
      );
    });
  });
}
