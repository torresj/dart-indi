import 'dart:async';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:indi/indi.dart';
import 'package:indi/testing.dart';
import 'package:test/test.dart';

import '../support/simulators.dart';

void main() {
  group('ReconnectPolicy', () {
    test('grows exponentially up to the maximum', () {
      const policy = ReconnectPolicy(
        initialDelay: Duration(seconds: 1),
        maxDelay: Duration(seconds: 10),
        jitter: 0,
      );
      expect(
        [for (var i = 1; i <= 6; i++) policy.delayFor(i).inSeconds],
        [1, 2, 4, 8, 10, 10],
      );
    });

    test('applies jitter within bounds', () {
      const policy = ReconnectPolicy(
        initialDelay: Duration(seconds: 10),
        jitter: 0.2,
      );
      final random = Random(3);
      for (var i = 0; i < 100; i++) {
        final delay = policy.delayFor(1, random).inMilliseconds;
        expect(delay, inInclusiveRange(8000, 12000));
      }
    });

    test('limits attempts', () {
      expect(const ReconnectPolicy(maxAttempts: 2).allows(2), isTrue);
      expect(const ReconnectPolicy(maxAttempts: 2).allows(3), isFalse);
      expect(const ReconnectPolicy().allows(1000), isTrue);
      expect(const ReconnectPolicy.disabled().allows(1), isFalse);
    });
  });

  group('reconnect and resume', () {
    late FakeIndiServer server;
    late IndiClient client;
    late IndiDevice mount;
    late IndiDevice camera;

    setUp(() async {
      server = FakeIndiServer();
      defineMount(server);
      defineCamera(server);
      client = IndiClient.withTransport(server.transport, options: fastOptions);
      (mount, camera) = await connectAndSync(client);
    });

    tearDown(() async {
      await client.close();
      await server.close();
    });

    test('reconnects and keeps the same device objects', () async {
      final states = <IndiConnectionState>[];
      client.connectionStates.listen(states.add);
      final resumed = client.eventsOf<SessionResumed>().first;

      await server.dropConnections();
      await eventually(() => !client.isConnected);
      expect(mount.isAvailable, isFalse);

      final event = await resumed;
      expect(client.isConnected, isTrue);
      expect(client.device(mountName), same(mount));
      expect(client.device(cameraName), same(camera));
      expect(mount.isAvailable, isTrue);
      expect(event.attempts, 1);
      expect(event.devices, containsAll([mount, camera]));
      expect(states.first, const IndiConnected());
      expect(states.skip(1).take(3).map((s) => s.runtimeType),
          [IndiReconnecting, IndiConnecting, IndiConnected]);
      final reconnecting = states[1] as IndiReconnecting;
      expect(reconnecting.attempt, 1);
      expect(reconnecting.error, isA<IndiConnectionLostException>());
    });

    test('removes what disappeared while disconnected', () async {
      final events = recordEvents(client);
      server.refuseConnections = true;
      await server.dropConnections();
      await eventually(() => client.connectionState is IndiReconnecting);
      server
        ..delete(mountName, 'STATUS')
        ..delete(cameraName);
      server.refuseConnections = false;
      await client.eventsOf<SessionResumed>().first;

      expect(mount['STATUS'], isNull);
      expect(mount.isAvailable, isTrue);
      expect(client.device(cameraName), isNull);
      expect(camera.isAvailable, isFalse);
      expect(
        events.whereType<PropertyRemoved>().map((e) => e.property.name),
        contains('STATUS'),
      );
      expect(
        events.whereType<DeviceRemoved>().map((e) => e.device.name),
        [cameraName],
      );
    });

    test('reports values that changed while disconnected', () async {
      server.refuseConnections = true;
      await server.dropConnections();
      await eventually(() => client.connectionState is IndiReconnecting);
      server.update(const SetNumberVector(
        device: mountName,
        name: 'EQUATORIAL_EOD_COORD',
        elements: [OneNumber(name: 'RA', value: 12)],
      ));
      final updated = mount
          .watch<NumberProperty>('EQUATORIAL_EOD_COORD')
          .firstWhere((p) => p.valueOf('RA') == 12);
      server.refuseConnections = false;
      await updated;
      await client.eventsOf<SessionResumed>().first;
      expect(mount.getNumber('EQUATORIAL_EOD_COORD')!.valueOf('RA'), 12);
    });

    test('pending commands fail and are never replayed', () async {
      final received = recordReceived(server);
      server.onNewVector = (command, server) async {
        await server.dropConnections();
        return const [];
      };
      await expectLater(
        mount.sendNumber('EQUATORIAL_EOD_COORD', 'RA', 1),
        throwsA(isA<IndiConnectionLostException>()),
      );
      await client.eventsOf<SessionResumed>().first;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(received.whereType<NewNumberVector>(), hasLength(1));
    });

    test('commands are rejected while reconnecting', () async {
      server.refuseConnections = true;
      await server.dropConnections();
      await eventually(() => client.connectionState is IndiReconnecting);
      expect(
        () => mount.setSwitch('TELESCOPE_TRACK_STATE', 'TRACK_ON'),
        throwsA(isA<IndiNotConnectedException>()),
      );
    });

    test('BLOB modes and watches are restored', () async {
      await camera.setBlobMode(BlobMode.also, property: 'CCD1');
      client.watchProperty(mountName, 'EQUATORIAL_EOD_COORD');
      client.watchDevice(cameraName);
      final received = recordReceived(server);
      await server.dropConnections();
      await client.eventsOf<SessionResumed>().first;
      expect(
        received.whereType<GetProperties>(),
        containsAll([
          const GetProperties(device: cameraName),
          const GetProperties(device: mountName, name: 'EQUATORIAL_EOD_COORD'),
        ]),
      );
      expect(
        received.whereType<EnableBlob>(),
        contains(const EnableBlob(
          mode: BlobMode.also,
          device: cameraName,
          name: 'CCD1',
        )),
      );
      expect(
        server.connections.single.blobMode(cameraName, 'CCD1'),
        BlobMode.also,
      );
    });

    test('gives up after maxAttempts and can connect again', () async {
      final limited = IndiClient.withTransport(
        server.transport,
        options: const IndiClientOptions(
          heartbeat: HeartbeatOptions.disabled(),
          resumeSettleTime: Duration(milliseconds: 20),
          reconnect: ReconnectPolicy(
            initialDelay: Duration(milliseconds: 5),
            maxAttempts: 2,
            jitter: 0,
          ),
        ),
      );
      addTearDown(limited.close);
      final (limitedMount, _) = await connectAndSync(limited);
      server.refuseConnections = true;
      await server.dropConnections();
      await eventually(() => limited.connectionState is IndiDisconnected);
      final state = limited.connectionState as IndiDisconnected;
      expect(state.error, isA<IndiConnectionException>());
      expect(limitedMount.isAvailable, isFalse);

      server
        ..refuseConnections = false
        ..delete(mountName, 'STATUS');
      final resumed = limited.eventsOf<SessionResumed>().first;
      await limited.connect();
      await resumed;
      expect(limited.device(mountName), same(limitedMount));
      expect(limitedMount['STATUS'], isNull);
    });

    test('a disabled policy does not reconnect', () async {
      final own = FakeIndiServer();
      addTearDown(own.close);
      final once = IndiClient.withTransport(
        own.transport,
        options: const IndiClientOptions(
          heartbeat: HeartbeatOptions.disabled(),
          reconnect: ReconnectPolicy.disabled(),
        ),
      );
      addTearDown(once.close);
      await once.connect();
      await own.dropConnections();
      await eventually(() => once.connectionState is IndiDisconnected);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(own.transport.connectAttempts, 1);
    });

    test('disconnect during reconnection stops it', () async {
      server.refuseConnections = true;
      await server.dropConnections();
      await eventually(() => client.connectionState is IndiReconnecting);
      await client.disconnect();
      final attempts = server.transport.connectAttempts;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(server.transport.connectAttempts, attempts);
      expect(client.connectionState, const IndiDisconnected());
    });
  });

  group('heartbeat', () {
    const options = IndiClientOptions(
      heartbeat: HeartbeatOptions(interval: Duration(seconds: 10)),
      reconnect: ReconnectPolicy(initialDelay: Duration(seconds: 1), jitter: 0),
      resumeSettleTime: Duration(seconds: 1),
    );

    test('pings regularly and reconnects when the server goes silent', () {
      fakeAsync((async) {
        final server = FakeIndiServer();
        defineMount(server);
        final client =
            IndiClient.withTransport(server.transport, options: options);
        final received = recordReceived(server);
        final states = <IndiConnectionState>[];
        client.connectionStates.listen(states.add);
        unawaited(client.connect());
        async.flushMicrotasks();
        expect(client.isConnected, isTrue);

        async.elapse(const Duration(seconds: 25));
        expect(received.whereType<PingRequest>(), hasLength(2));
        expect(client.isConnected, isTrue);

        // The link dies silently at t=25s: nothing arrives anymore. The last
        // data came at t=20s, so the 30s timeout expires at the t=60s tick.
        server.answerPings = false;
        async.elapse(const Duration(seconds: 34));
        expect(server.transport.connectAttempts, 1);
        async.elapse(const Duration(seconds: 2));
        expect(states.whereType<IndiReconnecting>().single.error,
            isA<IndiConnectionLostException>());
        expect(server.transport.connectAttempts, 2);
        expect(client.isConnected, isTrue);

        unawaited(client.close());
        unawaited(server.close());
        async.flushMicrotasks();
      });
    });

    test('stops pinging servers that never answer and keeps the link', () {
      fakeAsync((async) {
        final server = FakeIndiServer()..answerPings = false;
        defineMount(server);
        final client =
            IndiClient.withTransport(server.transport, options: options);
        final received = recordReceived(server);
        unawaited(client.connect());
        async.elapse(const Duration(minutes: 5));
        expect(received.whereType<PingRequest>(), hasLength(2));
        expect(client.isConnected, isTrue);
        expect(server.transport.connectAttempts, 1);
        unawaited(client.close());
        unawaited(server.close());
        async.flushMicrotasks();
      });
    });

    test('resume settles after the quiet period', () {
      fakeAsync((async) {
        final server = FakeIndiServer();
        defineMount(server);
        final client =
            IndiClient.withTransport(server.transport, options: options);
        final events = recordEvents(client);
        unawaited(client.connect());
        async.flushMicrotasks();
        unawaited(server.dropConnections());
        async.elapse(const Duration(milliseconds: 1500));
        expect(client.isConnected, isTrue);
        expect(events.whereType<SessionResumed>(), isEmpty);
        async.elapse(const Duration(seconds: 1));
        final resumed = events.whereType<SessionResumed>().single;
        expect(resumed.downtime, const Duration(seconds: 1));
        unawaited(client.close());
        unawaited(server.close());
        async.flushMicrotasks();
      });
    });
  });

  test('connectionStates emits the current state first', () async {
    final server = FakeIndiServer();
    final client =
        IndiClient.withTransport(server.transport, options: fastOptions);
    addTearDown(server.close);
    expect(await client.connectionStates.first, const IndiDisconnected());
    final states = client.connectionStates.take(3).toList();
    await client.connect();
    expect(await states, [
      const IndiDisconnected(),
      const IndiConnecting(),
      const IndiConnected(),
    ]);
    await client.close();
  });
}
