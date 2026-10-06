import 'package:indi/indi.dart';
import 'package:indi/testing.dart';
import 'package:test/test.dart';

import '../support/simulators.dart';

void expectValueSemantics(Object a, Object sameAsA, Object different) {
  expect(a, sameAsA);
  expect(a.hashCode, sameAsA.hashCode);
  expect(a, isNot(different));
  expect(a.toString(), isNotEmpty);
}

void main() {
  test('connection states have value semantics', () {
    final error = StateError('x');
    expectValueSemantics(
      IndiDisconnected(error: error),
      IndiDisconnected(error: error),
      const IndiDisconnected(),
    );
    expectValueSemantics(
      const IndiConnecting(attempt: 2),
      const IndiConnecting(attempt: 2),
      const IndiConnecting(),
    );
    expectValueSemantics(
      const IndiConnected(),
      const IndiConnected(),
      const IndiClosed(),
    );
    expectValueSemantics(
      const IndiReconnecting(attempt: 1, delay: Duration(seconds: 1)),
      const IndiReconnecting(attempt: 1, delay: Duration(seconds: 1)),
      const IndiReconnecting(attempt: 2, delay: Duration(seconds: 1)),
    );
    expectValueSemantics(
      const IndiClosed(),
      const IndiClosed(),
      const IndiConnected(),
    );
    expect(const IndiConnected().isConnected, isTrue);
    expect(const IndiReconnecting(attempt: 1, delay: Duration.zero).isConnected,
        isFalse);
    expect(
      IndiReconnecting(attempt: 3, delay: Duration.zero, error: error)
          .toString(),
      contains('error: Bad state: x'),
    );
    expect(IndiDisconnected(error: error).toString(), contains('Bad state'));
  });

  test('events describe themselves', () async {
    final server = FakeIndiServer();
    defineMount(server);
    defineCamera(server);
    final client =
        IndiClient.withTransport(server.transport, options: fastOptions);
    addTearDown(() async {
      await client.close();
      await server.close();
    });
    final events = recordEvents(client);
    final (mount, _) = await connectAndSync(client);
    server
      ..update(const SetSwitchVector(
        device: mountName,
        name: 'TELESCOPE_TRACK_STATE',
        state: PropertyState.ok,
        elements: [],
      ))
      ..message('hello')
      ..delete(mountName, 'STATUS');
    await server.dropConnections();
    await client.eventsOf<SessionResumed>().first;
    server.connections.single.sendRaw('<oops/></x>'.codeUnits);
    await eventually(
        () => events.whereType<ProtocolErrorReceived>().isNotEmpty);
    server.delete(mountName);
    await eventually(() => events.whereType<DeviceRemoved>().isNotEmpty);

    final descriptions = events.map((e) => e.toString()).toList();
    expect(descriptions, contains('ConnectionStateChanged(IndiConnected())'));
    expect(descriptions, contains('DeviceAdded($mountName)'));
    expect(descriptions, contains('PropertyDefined($mountName.CONNECTION)'));
    expect(
      descriptions,
      contains('PropertyUpdated($mountName.TELESCOPE_TRACK_STATE, '
          'PropertyState.ok)'),
    );
    expect(descriptions, contains('PropertyRemoved($mountName.STATUS)'));
    expect(descriptions, contains('MessageReceived(hello)'));
    expect(descriptions, contains('DeviceRemoved($mountName)'));
    expect(
      descriptions.where((d) => d.startsWith('SessionResumed(downtime: ')),
      hasLength(1),
    );
    expect(
      descriptions.where((d) => d.startsWith('ProtocolErrorReceived(')),
      isNotEmpty,
    );
    expect(mount.isRemoved, isTrue);
  });

  test('wrapper values have value semantics', () {
    expectValueSemantics(
      const EquatorialCoordinates(raHours: 1, decDegrees: 2),
      const EquatorialCoordinates(raHours: 1, decDegrees: 2),
      const EquatorialCoordinates(raHours: 1, decDegrees: 3),
    );
    expectValueSemantics(
      const HorizontalCoordinates(altitudeDegrees: 1, azimuthDegrees: 2),
      const HorizontalCoordinates(altitudeDegrees: 1, azimuthDegrees: 2),
      const HorizontalCoordinates(altitudeDegrees: 2, azimuthDegrees: 2),
    );
    expectValueSemantics(
      const GeographicLocation(latitudeDegrees: 1, longitudeDegrees: 2),
      const GeographicLocation(latitudeDegrees: 1, longitudeDegrees: 2),
      const GeographicLocation(
        latitudeDegrees: 1,
        longitudeDegrees: 2,
        elevationMeters: 3,
      ),
    );
    expectValueSemantics(
      const SensorFrame(x: 0, y: 0, width: 10, height: 20),
      const SensorFrame(x: 0, y: 0, width: 10, height: 20),
      const SensorFrame(x: 1, y: 0, width: 10, height: 20),
    );
    expectValueSemantics(
      const SensorInfo(
        width: 10,
        height: 20,
        pixelSizeX: 3.8,
        pixelSizeY: 3.8,
        bitsPerPixel: 16,
      ),
      const SensorInfo(
        width: 10,
        height: 20,
        pixelSizeX: 3.8,
        pixelSizeY: 3.8,
        bitsPerPixel: 16,
      ),
      const SensorInfo(
        width: 10,
        height: 20,
        pixelSizeX: 3.8,
        pixelSizeY: 3.8,
        bitsPerPixel: 8,
      ),
    );
    expect(const SensorFrame(x: 1, y: 2, width: 3, height: 4).toString(),
        'SensorFrame(1, 2, 3x4)');
  });
}
