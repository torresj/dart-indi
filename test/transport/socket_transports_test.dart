// Tests the real TCP and WebSocket transports, by bridging local sockets to
// a FakeIndiServer.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:indi/indi.dart';
import 'package:indi/testing.dart';
import 'package:test/test.dart';

import '../support/simulators.dart';

/// Serves [server] on a local TCP port, like indiserver.
Future<ServerSocket> tcpBridge(FakeIndiServer server) async {
  final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  listener.listen((socket) async {
    final connection = await server.transport.connect();
    connection.input.listen(socket.add, onDone: socket.destroy);
    socket.listen(connection.add, onDone: connection.close);
  });
  return listener;
}

/// Serves [server] through WebSockets, like websockify.
Future<HttpServer> webSocketBridge(
  FakeIndiServer server, {
  bool textFrames = false,
}) async {
  final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  http.listen((request) async {
    final socket = await WebSocketTransformer.upgrade(request);
    final connection = await server.transport.connect();
    connection.input.listen(
      (bytes) => socket.add(textFrames ? utf8.decode(bytes) : bytes),
      onDone: socket.close,
    );
    socket.listen(
      (data) => connection.add(
        data is String ? utf8.encode(data) : data as List<int>,
      ),
      onDone: connection.close,
    );
  });
  return http;
}

void main() {
  late FakeIndiServer server;

  setUp(() {
    server = FakeIndiServer();
    defineMount(server);
    defineCamera(server);
  });

  tearDown(() => server.close());

  group('TcpTransport', () {
    test('runs a session over TCP', () async {
      final listener = await tcpBridge(server);
      addTearDown(listener.close);
      final client = IndiClient(
        port: listener.port,
        options: fastOptions,
      );
      addTearDown(client.close);
      expect(client.transport, isA<TcpTransport>());
      final (mount, camera) = await connectAndSync(client);
      await mount.setSwitch('TELESCOPE_TRACK_STATE', 'TRACK_ON');
      expect(
          mount.getSwitch('TELESCOPE_TRACK_STATE')!.isOn('TRACK_ON'), isTrue);

      // A large image crosses many TCP segments.
      final image = Uint8List.fromList(
        List.generate(3 * 1024 * 1024, (i) => i & 0xFF),
      );
      await camera.setBlobMode(BlobMode.also, property: 'CCD1');
      await eventually(() =>
          server.connections.single.blobMode(
            cameraName,
            'CCD1',
          ) ==
          BlobMode.also);
      final received = camera.watch<BlobProperty>('CCD1').skip(1).first;
      server.update(SetBlobVector(
        device: cameraName,
        name: 'CCD1',
        elements: [OneBlob(name: 'CCD1', format: '.fits', data: image)],
      ));
      expect((await received)['CCD1']!.blob!.bytes, image);
    });

    test('reconnects when the server closes the socket', () async {
      final listener = await tcpBridge(server);
      addTearDown(listener.close);
      final client = IndiClient(port: listener.port, options: fastOptions);
      addTearDown(client.close);
      final (mount, _) = await connectAndSync(client);
      final resumed = client.eventsOf<SessionResumed>().first;
      await server.dropConnections();
      await resumed;
      expect(client.device(mountName), same(mount));
      expect(mount.isAvailable, isTrue);
    });

    test('fails to connect to a closed port', () async {
      final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = listener.port;
      await listener.close();
      final client = IndiClient(port: port);
      addTearDown(client.close);
      await expectLater(
        client.connect(),
        throwsA(isA<IndiConnectionException>()
            .having((e) => e.cause, 'cause', isA<SocketException>())),
      );
    });
  });

  group('WebSocketTransport', () {
    for (final textFrames in [false, true]) {
      test('runs a session (${textFrames ? 'text' : 'binary'} frames)',
          () async {
        final http = await webSocketBridge(server, textFrames: textFrames);
        addTearDown(http.close);
        final client = IndiClient.withTransport(
          WebSocketTransport(Uri.parse('ws://localhost:${http.port}')),
          options: fastOptions,
        );
        addTearDown(client.close);
        final (mount, _) = await connectAndSync(client);
        await mount.sendNumber('EQUATORIAL_EOD_COORD', 'RA', 7);
        expect(mount.getNumber('EQUATORIAL_EOD_COORD')!.valueOf('RA'), 7);
      });
    }

    test('fails to connect to a server that is not there', () async {
      final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = http.port;
      await http.close();
      final client = IndiClient.withTransport(
        WebSocketTransport(Uri.parse('ws://localhost:$port')),
      );
      addTearDown(client.close);
      await expectLater(
        client.connect(),
        throwsA(isA<IndiConnectionException>()),
      );
    });
  });
}
