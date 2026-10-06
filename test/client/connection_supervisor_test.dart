import 'package:indi/indi.dart';
import 'package:indi/src/client/connection_supervisor.dart';
import 'package:indi/testing.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

void main() {
  test('a closed supervisor refuses to start', () async {
    final server = FakeIndiServer();
    addTearDown(server.close);
    final states = <IndiConnectionState>[];
    final supervisor = ConnectionSupervisor(
      transport: server.transport,
      connectTimeout: const Duration(seconds: 1),
      reconnect: const ReconnectPolicy.disabled(),
      heartbeat: const HeartbeatOptions.disabled(),
      retryInitialConnect: false,
      onCommand: (_) {},
      onProtocolError: (_) {},
      onConnected: ({required isReconnect, required attempts}) {},
      onConnectionLost: (_) {},
      onStateChanged: states.add,
      logger: Logger('test'),
    );
    await supervisor.start();
    await supervisor.close();
    await supervisor.close();
    await supervisor.stop();
    await expectLater(
      supervisor.start(),
      throwsA(isA<IndiClosedException>()),
    );
    expect(states, [
      const IndiConnecting(),
      const IndiConnected(),
      const IndiDisconnected(),
      const IndiClosed(),
    ]);
  });
}
