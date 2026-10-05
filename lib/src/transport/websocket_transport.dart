import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../exceptions.dart';
import 'transport.dart';

/// Connects to an INDI server through a WebSocket.
///
/// This is how Flutter web apps reach INDI, since browsers can't open raw
/// TCP sockets. indiserver does not speak WebSocket itself; put a bridge
/// such as [websockify](https://github.com/novnc/websockify) in front of it:
///
/// ```sh
/// websockify 8624 localhost:7624
/// ```
///
/// and connect to `ws://<host>:8624`. Works on every platform.
///
/// {@category Transports}
final class WebSocketTransport implements IndiTransport {
  /// Creates a transport for the WebSocket endpoint at [uri].
  const WebSocketTransport(this.uri, {this.protocols});

  /// The WebSocket URI, such as `ws://raspberrypi.local:8624`.
  final Uri uri;

  /// Optional WebSocket subprotocols to request.
  final Iterable<String>? protocols;

  @override
  String get description => uri.toString();

  @override
  Future<IndiConnection> connect({Duration? timeout}) async {
    final WebSocketChannel channel;
    try {
      channel = WebSocketChannel.connect(uri, protocols: protocols);
      final ready = channel.ready;
      await (timeout == null ? ready : ready.timeout(timeout));
    } on Object catch (e) {
      throw IndiConnectionException('Cannot connect to $description', cause: e);
    }
    return _WebSocketConnection(channel);
  }

  @override
  String toString() => 'WebSocketTransport($description)';
}

final class _WebSocketConnection implements IndiConnection {
  _WebSocketConnection(this._channel) {
    _done = _channel.sink.done.then<void>((_) {}, onError: (Object _) {});
  }

  final WebSocketChannel _channel;
  late final Future<void> _done;
  bool _closed = false;

  @override
  late final Stream<Uint8List> input = _channel.stream.map(
    (message) => switch (message) {
      Uint8List() => message,
      List<int>() => Uint8List.fromList(message),
      String() => utf8.encode(message),
      _ => throw IndiProtocolException(
          'Unexpected WebSocket message of type ${message.runtimeType}',
        ),
    },
  );

  @override
  void add(List<int> bytes) {
    if (_closed) return;
    try {
      _channel.sink.add(bytes is Uint8List ? bytes : Uint8List.fromList(bytes));
    } on Object {
      // The channel is already closed; `done` and `input` report it.
    }
  }

  @override
  Future<void> close() async {
    if (!_closed) {
      _closed = true;
      unawaited(_channel.sink.close().then<void>((_) {}, onError: (_) {}));
    }
    return _done;
  }

  @override
  Future<void> get done => _done;
}
