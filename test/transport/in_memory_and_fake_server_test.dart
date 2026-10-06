import 'package:indi/indi.dart';
import 'package:indi/testing.dart';
import 'package:test/test.dart';

import '../support/simulators.dart';

void main() {
  test('an in-memory connection reports failures on both sides', () async {
    final (client, server) = InMemoryConnection.pair();
    final clientErrors = <Object>[];
    final serverErrors = <Object>[];
    client.input.listen(null, onError: clientErrors.add);
    server.input.listen(null, onError: serverErrors.add);
    server.fail(StateError('broken'));
    await client.done;
    await Future<void>.delayed(Duration.zero);
    expect(clientErrors.single, isA<StateError>());
    expect(serverErrors.single, isA<StateError>());
    expect(client.isClosed, isTrue);
    client.add([1, 2, 3]); // Ignored once closed.
  });

  test('FakeIndiServer exposes its state and custom replies', () async {
    final server = FakeIndiServer();
    addTearDown(server.close);
    defineMount(server);
    defineCamera(server);
    expect(server.devices, {mountName, cameraName});
    expect(server.refuseConnections, isFalse);

    final client =
        IndiClient.withTransport(server.transport, options: fastOptions);
    addTearDown(client.close);
    final (mount, _) = await connectAndSync(client);
    // A handler can answer with any command, not only updates.
    server.onNewVector = (command, server) => [
          MessageCommand(device: command.device, message: 'Busy elsewhere'),
          SetSwitchVector(
            device: command.device,
            name: command.name,
            state: PropertyState.alert,
            elements: const [],
          ),
        ];
    await expectLater(
      mount.setSwitch('TELESCOPE_TRACK_STATE', 'TRACK_ON'),
      throwsA(isA<IndiPropertyAlertException>()),
    );
    expect(mount.messages.single.text, 'Busy elsewhere');
    expect(server.connections.single.protocolErrors, isEmpty);
  });

  test('transports describe themselves', () {
    expect(const TcpTransport('scope.local').toString(),
        'TcpTransport(tcp://scope.local:7624)');
    expect(
      WebSocketTransport(Uri.parse('ws://scope.local:8624')).toString(),
      'WebSocketTransport(ws://scope.local:8624)',
    );
  });
}
