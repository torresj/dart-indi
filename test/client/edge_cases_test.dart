import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:indi/indi.dart';
import 'package:indi/testing.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import '../support/simulators.dart';

/// A transport whose connections fail with a non-INDI error.
final class _BrokenTransport implements IndiTransport {
  @override
  String get description => 'broken://';

  @override
  Future<IndiConnection> connect({Duration? timeout}) =>
      Future.error(StateError('no route to host'));
}

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
    test('concurrent connect calls share one attempt', () async {
      server.transport.connectDelay = const Duration(milliseconds: 20);
      await Future.wait([client.connect(), client.connect()]);
      expect(server.transport.connectAttempts, 1);
      await client.connect();
      expect(server.transport.connectAttempts, 1);
    });

    test('disconnect while connecting cancels the attempt', () async {
      server.transport.connectDelay = const Duration(milliseconds: 30);
      final connecting = client.connect();
      final failed = expectLater(
        connecting,
        throwsA(isA<IndiConnectionException>()),
      );
      await client.disconnect();
      await failed;
      // The connection that arrives late is closed at once.
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(server.connections, isEmpty);
      expect(client.connectionState, const IndiDisconnected());
    });

    test('wraps transport errors in IndiConnectionException', () async {
      final broken = IndiClient.withTransport(_BrokenTransport());
      addTearDown(broken.close);
      await expectLater(
        broken.connect(),
        throwsA(isA<IndiConnectionException>()
            .having((e) => e.cause, 'cause', isA<StateError>())
            .having((e) => e.toString(), 'toString', contains('no route'))),
      );
    });

    test('a network error reconnects with that error', () async {
      final (mount, _) = await connectAndSync(client);
      final reconnecting = client.connectionStates
          .firstWhere((state) => state is IndiReconnecting);
      final resumed = client.eventsOf<SessionResumed>().first;
      server.connections.single.fail(StateError('cable unplugged'));
      final state = await reconnecting as IndiReconnecting;
      expect(state.error, isA<StateError>());
      await resumed;
      expect(mount.isAvailable, isTrue);
    });
  });

  group('model edge cases', () {
    late IndiDevice mount;

    setUp(() async => (mount, _) = await connectAndSync(client));

    test('a property redefined with another type is replaced', () async {
      final events = recordEvents(client);
      server.define(const DefTextVector(
        device: mountName,
        name: 'EQUATORIAL_EOD_COORD',
        elements: [DefText(name: 'RA', value: '5h')],
      ));
      await eventually(() => mount['EQUATORIAL_EOD_COORD'] is TextProperty);
      await eventually(() => events.length >= 2);
      expect(events[0], isA<PropertyRemoved>());
      expect((events[0] as PropertyRemoved).property, isA<NumberProperty>());
      expect(events[1], isA<PropertyDefined>());
    });

    test('a pending command fails if its property changes type', () async {
      server.onNewVector = (command, server) {
        server.define(DefTextVector(
          device: command.device,
          name: command.name,
          state: PropertyState.ok,
          elements: const [DefText(name: 'RA')],
        ));
        return const [];
      };
      await expectLater(
        mount.sendNumber('EQUATORIAL_EOD_COORD', 'RA', 1),
        throwsA(isA<IndiProtocolException>()
            .having((e) => e.message, 'message', contains('Text'))),
      );
    });

    test('an Alert without a message gets a default explanation', () async {
      server.onNewVector = (command, server) => [
            SetSwitchVector(
              device: command.device,
              name: command.name,
              state: PropertyState.alert,
              elements: const [],
            ),
          ];
      await expectLater(
        mount.setSwitch('TELESCOPE_TRACK_STATE', 'TRACK_ON'),
        throwsA(isA<IndiPropertyAlertException>().having(
          (e) => e.message,
          'message',
          '"$mountName.TELESCOPE_TRACK_STATE" went to Alert',
        )),
      );
    });

    test('commands the server should not send are ignored', () async {
      final commands = <IndiCommand>[];
      client.commands.listen(commands.add);
      final connection = server.connections.single
        ..send(const NewNumberVector(
          device: mountName,
          name: 'EQUATORIAL_EOD_COORD',
          elements: [OneNumber(name: 'RA', value: 23)],
        ))
        ..send(const GetProperties(device: mountName))
        ..send(const EnableBlob(mode: BlobMode.also, device: mountName))
        ..send(const UnknownCommand(tag: 'futureCommand'));
      connection.send(const PingRequest(uid: 'sync'));
      await eventually(() => commands.length == 5);
      expect(mount.getNumber('EQUATORIAL_EOD_COORD')!.valueOf('RA'), 5.5);
      expect(client.isConnected, isTrue);
    });

    test('groups and properties by group', () {
      expect(
        mount.propertiesIn('Main Control').map((p) => p.name),
        [
          'CONNECTION',
          'EQUATORIAL_EOD_COORD',
          'TELESCOPE_TRACK_STATE',
          'STATUS'
        ],
      );
      expect(mount.propertiesIn('Nope'), isEmpty);
    });

    test('driver information has value semantics', () {
      final info = mount.driverInfo!;
      expect(info, mount.driverInfo);
      expect(info.hashCode, mount.driverInfo.hashCode);
      expect(info.toString(), contains('indi_simulator_telescope'));
      expect(info.toString(), contains('telescope, guider'));
      expect(mount.toString(), 'IndiDevice($mountName)');
      expect(client.toString(), 'IndiClient(memory://indi)');
    });
  });

  group('commands', () {
    late IndiDevice mount;
    late IndiDevice camera;

    setUp(() async => (mount, camera) = await connectAndSync(client));

    test('afterBusy matches texts and switches by value', () async {
      final port = await mount.sendText(
        'DEVICE_PORT',
        'PORT',
        '/dev/ttyACM0',
        completion: CommandCompletion.afterBusy,
      );
      expect(port.valueOf('PORT'), '/dev/ttyACM0');
      final frame = await camera.sendSwitches(
        'CCD_FRAME_TYPE',
        {'FRAME_DARK': true},
        completion: CommandCompletion.afterBusy,
      );
      expect(frame.activeElement?.name, 'FRAME_DARK');
    });

    test('afterBusy never matches BLOB uploads by value', () async {
      server.define(const DefBlobVector(
        device: cameraName,
        name: 'UPLOAD',
        perm: PropertyPermission.writeOnly,
        elements: [DefBlob(name: 'FILE')],
      ));
      await camera.waitForProperty<BlobProperty>('UPLOAD');
      await camera.setBlobMode(BlobMode.also, property: 'UPLOAD');
      server.onNewVector = (command, server) => [
            SetBlobVector(
              device: command.device,
              name: command.name,
              state: PropertyState.busy,
              elements: const [],
            ),
            SetBlobVector(
              device: command.device,
              name: command.name,
              state: PropertyState.ok,
              elements: const [],
            ),
          ];
      final result = await camera.sendBlobs(
        'UPLOAD',
        {
          'FILE': IndiBlob(Uint8List.fromList([1]), format: '.bin')
        },
        completion: CommandCompletion.afterBusy,
      );
      expect(result.state, PropertyState.ok);
    });

    test('AtMostOne allows turning everything off but not two on', () async {
      server.define(const DefSwitchVector(
        device: mountName,
        name: 'TELESCOPE_MOTION_NS',
        rule: SwitchRule.atMostOne,
        elements: [
          DefSwitch(name: 'MOTION_NORTH', state: SwitchState.on),
          DefSwitch(name: 'MOTION_SOUTH', state: SwitchState.off),
        ],
      ));
      await mount.waitForProperty<SwitchProperty>('TELESCOPE_MOTION_NS');
      expect(
        () => mount.sendSwitches(
          'TELESCOPE_MOTION_NS',
          {'MOTION_NORTH': true, 'MOTION_SOUTH': true},
        ),
        throwsA(isA<IndiValidationException>()),
      );
      final off = await mount.setSwitch(
        'TELESCOPE_MOTION_NS',
        'MOTION_NORTH',
        on: false,
      );
      expect(off.activeElement, isNull);
    });
  });

  group('waiting and watching', () {
    test('waitForDevice succeeds before its timeout', () async {
      final waiting = client.waitForDevice(
        mountName,
        timeout: const Duration(seconds: 5),
      );
      await client.connect();
      expect((await waiting).name, mountName);
    });

    test('streams and waits after closing', () async {
      await connectAndSync(client);
      final mount = client.device(mountName)!;
      await client.close();
      expect(await mount.watch<NumberProperty>('EQUATORIAL_EOD_COORD').toList(),
          isEmpty);
      await expectLater(
        client.waitForDevice('Nobody'),
        throwsA(isA<IndiClosedException>()),
      );
      expect(await client.connectionStates.toList(), [const IndiClosed()]);
    });

    test('a pending ping fails when the client closes', () async {
      server.answerPings = false;
      await client.connect();
      final ping = expectLater(
        client.ping(timeout: const Duration(seconds: 5)),
        throwsA(isA<IndiClosedException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await client.close();
      await ping;
    });

    test('watching a property also accepts messages of its device', () async {
      final watching = IndiClient.withTransport(
        server.transport,
        options: fastOptions,
      )..watchProperty(cameraName, 'CCD_TEMPERATURE');
      addTearDown(watching.close);
      await watching.connect();
      final camera = await watching.waitForDevice(cameraName);
      await camera.waitForProperty<NumberProperty>('CCD_TEMPERATURE');
      server
        ..message('for the mount', device: mountName)
        ..message('for the camera', device: cameraName);
      await eventually(() => watching.messages.isNotEmpty);
      expect(watching.messages.single.text, 'for the camera');
      expect(camera.properties.keys, ['CCD_TEMPERATURE']);
      expect(watching.device(mountName), isNull);
    });
  });

  group('separate BLOB connection', () {
    const options = IndiClientOptions(
      separateBlobConnection: true,
      heartbeat: HeartbeatOptions.disabled(),
      reconnect: ReconnectPolicy(
        initialDelay: Duration(milliseconds: 10),
        jitter: 0,
      ),
      resumeSettleTime: Duration(milliseconds: 50),
    );

    SetBlobVector image(int value) => SetBlobVector(
          device: cameraName,
          name: 'CCD1',
          elements: [
            OneBlob(
              name: 'CCD1',
              format: '.fits',
              data: Uint8List.fromList([value]),
            ),
          ],
        );

    test('applies BLOB modes set before connecting and after a drop', () async {
      final split =
          IndiClient.withTransport(server.transport, options: options);
      addTearDown(split.close);
      await split.setBlobMode(
        BlobMode.also,
        device: cameraName,
        property: 'CCD1',
      );
      final (_, camera) = await connectAndSync(split);
      bool blobConnectionReady() => server.connections.any(
            (c) => c.blobMode(cameraName, 'CCD1') == BlobMode.only,
          );
      await eventually(blobConnectionReady);

      await server.dropConnections();
      await split.eventsOf<SessionResumed>().first;
      await eventually(blobConnectionReady);
      server.update(image(7));
      await eventually(
        () => camera.getBlob('CCD1')!['CCD1']!.blob?.bytes.first == 7,
      );
    });

    test('retries the BLOB connection in the background', () async {
      final blobServer = FakeIndiServer()..refuseConnections = true;
      addTearDown(blobServer.close);
      // The BLOB connection goes through a bridge to the same server.
      final bridge = InMemoryTransport(onConnect: (side) async {
        final upstream = await server.transport.connect();
        upstream.input.listen(side.add, onDone: side.close);
        side.input.listen(upstream.add, onDone: upstream.close);
      });
      var refuse = true;
      final flaky = _ToggleTransport(bridge, () => refuse);
      final split = IndiClient.withTransport(
        server.transport,
        blobTransport: flaky,
        options: options,
      );
      addTearDown(split.close);
      final (_, camera) = await connectAndSync(split);
      await camera.setBlobMode(BlobMode.also, property: 'CCD1');
      await eventually(() => flaky.attempts >= 2);
      refuse = false;
      await eventually(() => server.connections.length == 2);
      await eventually(() => server.connections.any(
            (c) => c.blobMode(cameraName, 'CCD1') == BlobMode.only,
          ));
    });

    test('logs when the BLOB connection gives up', () async {
      final records = <LogRecord>[];
      final subscription = Logger.root.onRecord.listen(records.add);
      addTearDown(subscription.cancel);
      final split = IndiClient.withTransport(
        server.transport,
        blobTransport: _BrokenTransport(),
        options: const IndiClientOptions(
          separateBlobConnection: true,
          heartbeat: HeartbeatOptions.disabled(),
          reconnect: ReconnectPolicy(
            initialDelay: Duration(milliseconds: 5),
            maxAttempts: 1,
            jitter: 0,
          ),
        ),
      );
      addTearDown(split.close);
      await split.connect();
      await eventually(
        () => records.any((r) => r.message.contains('BLOB connection failed')),
      );
      expect(split.isConnected, isTrue);
    });
  });

  test('resume ends at resumeMaxSettleTime even if definitions continue', () {
    fakeAsync((async) {
      final server = FakeIndiServer();
      defineMount(server);
      final client = IndiClient.withTransport(
        server.transport,
        options: const IndiClientOptions(
          heartbeat: HeartbeatOptions.disabled(),
          reconnect: ReconnectPolicy(
            initialDelay: Duration(seconds: 1),
            jitter: 0,
          ),
          resumeSettleTime: Duration(seconds: 1),
          resumeMaxSettleTime: Duration(seconds: 3),
        ),
      );
      final events = recordEvents(client);
      unawaited(client.connect());
      async.flushMicrotasks();
      unawaited(server.dropConnections());
      async.elapse(const Duration(seconds: 1)); // reconnected
      // A chatty driver keeps defining properties every half second.
      final chatter = Timer.periodic(const Duration(milliseconds: 500), (t) {
        server.define(DefTextVector(
          device: mountName,
          name: 'CHATTER_${t.tick}',
          elements: const [DefText(name: 'X')],
        ));
      });
      async.elapse(const Duration(milliseconds: 2900));
      expect(events.whereType<SessionResumed>(), isEmpty);
      async.elapse(const Duration(milliseconds: 200));
      expect(events.whereType<SessionResumed>(), hasLength(1));
      chatter.cancel();
      unawaited(client.close());
      unawaited(server.close());
      async.flushMicrotasks();
    });
  });
}

/// Refuses connections while `refuse` returns `true`, then delegates.
final class _ToggleTransport implements IndiTransport {
  _ToggleTransport(this._inner, this._refuse);

  final IndiTransport _inner;
  final bool Function() _refuse;
  int attempts = 0;

  @override
  String get description => 'toggle://';

  @override
  Future<IndiConnection> connect({Duration? timeout}) {
    attempts++;
    if (_refuse()) {
      return Future.error(const IndiConnectionException('refused'));
    }
    return _inner.connect(timeout: timeout);
  }
}
