import 'dart:async';
import 'dart:typed_data';

/// Opens byte connections to an INDI server.
///
/// The package includes [IndiTransport] implementations for TCP
/// (`TcpTransport`, not available on the web), WebSockets
/// (`WebSocketTransport`, every platform) and memory (`InMemoryTransport`,
/// for tests). Implement this interface to tunnel INDI through anything
/// else, such as SSH or a serial bridge.
///
/// {@category Transports}
abstract interface class IndiTransport {
  /// Opens a new connection.
  ///
  /// Throws an `IndiConnectionException` if the server can't be reached
  /// within [timeout].
  Future<IndiConnection> connect({Duration? timeout});

  /// A short description of the endpoint for logs, such as
  /// `tcp://localhost:7624`.
  String get description;
}

/// An open, bidirectional byte connection to an INDI server.
///
/// {@category Transports}
abstract interface class IndiConnection {
  /// The bytes received from the server. Single subscription; it closes
  /// when the connection closes and reports transport errors.
  Stream<Uint8List> get input;

  /// Sends [bytes] to the server.
  ///
  /// Write errors are reported through [done] and [input], not thrown.
  void add(List<int> bytes);

  /// Closes the connection. Safe to call more than once.
  Future<void> close();

  /// Completes when the connection is closed, by either side.
  Future<void> get done;
}
