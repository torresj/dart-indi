import 'dart:async';
import 'dart:typed_data';

import '../exceptions.dart';
import 'transport.dart';

/// A transport that connects to an in-process server, for tests.
///
/// Every successful [connect] creates a connected pair: the client side is
/// returned and the server side is passed to `onConnect`. `FakeIndiServer`
/// builds on this to simulate INDI devices.
///
/// {@category Testing}
final class InMemoryTransport implements IndiTransport {
  /// Creates a transport that hands the server side of each new connection
  /// to [onConnect].
  InMemoryTransport({required this.onConnect});

  /// Called with the server side of each new connection.
  final void Function(InMemoryConnection serverSide) onConnect;

  /// When `true`, [connect] fails as if the server were unreachable.
  bool refuseConnections = false;

  /// An artificial delay before [connect] completes.
  Duration connectDelay = Duration.zero;

  /// The number of connection attempts made so far, including refused ones.
  int get connectAttempts => _connectAttempts;
  int _connectAttempts = 0;

  @override
  String get description => 'memory://indi';

  @override
  Future<IndiConnection> connect({Duration? timeout}) async {
    _connectAttempts++;
    if (connectDelay > Duration.zero) await Future<void>.delayed(connectDelay);
    if (refuseConnections) {
      throw const IndiConnectionException(
        'Cannot connect to memory://indi (refused)',
      );
    }
    final (client, server) = InMemoryConnection.pair();
    onConnect(server);
    return client;
  }
}

/// One side of an in-memory connection.
///
/// {@category Testing}
final class InMemoryConnection implements IndiConnection {
  InMemoryConnection._(this._incoming, this._outgoing, this._closer);

  /// Creates two connected ends: bytes added to one arrive on the other's
  /// [input].
  static (InMemoryConnection, InMemoryConnection) pair() {
    // Both controllers are closed by the shared _PairCloser.
    // ignore: close_sinks
    final toServer = StreamController<Uint8List>();
    // ignore: close_sinks
    final toClient = StreamController<Uint8List>();
    final closer = _PairCloser(toServer, toClient);
    return (
      InMemoryConnection._(toClient, toServer, closer),
      InMemoryConnection._(toServer, toClient, closer),
    );
  }

  final StreamController<Uint8List> _incoming;
  final StreamController<Uint8List> _outgoing;
  final _PairCloser _closer;

  @override
  Stream<Uint8List> get input => _incoming.stream;

  /// Whether the connection has been closed by either side.
  bool get isClosed => _closer.closed;

  @override
  void add(List<int> bytes) {
    if (_closer.closed) return;
    _outgoing.add(bytes is Uint8List ? bytes : Uint8List.fromList(bytes));
  }

  /// Simulates a network failure: both sides see [error] and the
  /// connection closes.
  void fail(Object error) => _closer.close(error);

  @override
  Future<void> close() => _closer.close();

  @override
  Future<void> get done => _closer.done.future;
}

final class _PairCloser {
  _PairCloser(this._a, this._b);

  final StreamController<Uint8List> _a;
  final StreamController<Uint8List> _b;
  final Completer<void> done = Completer<void>();
  bool closed = false;

  Future<void> close([Object? error]) {
    if (closed) return done.future;
    closed = true;
    for (final controller in [_a, _b]) {
      if (error != null) controller.addError(error);
      // The other side may never listen; don't wait for it.
      unawaited(controller.close());
    }
    done.complete();
    return done.future;
  }
}
