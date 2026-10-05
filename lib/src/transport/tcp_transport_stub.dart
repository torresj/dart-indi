import '../exceptions.dart';
import 'transport.dart';

/// Connects to an INDI server over TCP, the standard INDI transport.
///
/// Raw TCP sockets are not available on the web, where this class throws
/// on [connect]. Use `WebSocketTransport` there.
///
/// {@category Transports}
final class TcpTransport implements IndiTransport {
  /// Creates a transport for the server at [host]:[port].
  const TcpTransport(this.host, {this.port = 7624});

  /// The server host name or IP address.
  final String host;

  /// The server port.
  final int port;

  @override
  String get description => 'tcp://$host:$port';

  @override
  Future<IndiConnection> connect({Duration? timeout}) =>
      Future.error(const IndiConnectionException(
        'TCP sockets are not available on this platform; '
        'use WebSocketTransport',
      ));
}
