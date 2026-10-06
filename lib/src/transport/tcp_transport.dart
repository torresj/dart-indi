import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../exceptions.dart';
import 'transport.dart';

/// Connects to an INDI server over TCP, the standard INDI transport.
///
/// Available on Android, iOS, Linux, macOS, Windows and the Dart VM. On the
/// web use `WebSocketTransport` instead.
///
/// {@category Transports}
final class TcpTransport implements IndiTransport {
  /// Creates a transport for the server at [host]:[port].
  const TcpTransport(this.host, {this.port = 7624});

  /// The server host name or IP address.
  final String host;

  /// The server port. indiserver listens on 7624 by default.
  final int port;

  @override
  String get description => 'tcp://$host:$port';

  @override
  Future<IndiConnection> connect({Duration? timeout}) async {
    // Owned and closed by the returned connection.
    // ignore: close_sinks
    final Socket socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
    } on Object catch (e) {
      throw IndiConnectionException('Cannot connect to $description', cause: e);
    }
    // INDI messages are small and latency matters more than throughput.
    socket.setOption(SocketOption.tcpNoDelay, true);
    return _TcpConnection(socket);
  }

  @override
  String toString() => 'TcpTransport($description)';
}

final class _TcpConnection implements IndiConnection {
  _TcpConnection(this._socket) {
    // Write errors also complete `done`; don't let them escape as unhandled
    // errors.
    unawaited(
      _socket.done
          .then<void>((_) => _finish(), onError: (Object _) => _finish()),
    );
  }

  final Socket _socket;
  final Completer<void> _done = Completer<void>();
  bool _closed = false;

  void _finish() {
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Stream<Uint8List> get input => _socket;

  @override
  void add(List<int> bytes) {
    if (_closed) return;
    try {
      _socket.add(bytes);
    } on Object {
      // The socket is already closed; `done` and `input` report it.
    }
  }

  @override
  Future<void> close() {
    if (!_closed) {
      _closed = true;
      // destroy() tears the socket down at once. Its `done` future only
      // completes once the input was listened to, so don't wait for it.
      _socket.destroy();
      _finish();
    }
    return _done.future;
  }

  @override
  Future<void> get done => _done.future;
}
