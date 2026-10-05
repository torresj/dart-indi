import 'transport.dart';
import 'websocket_transport.dart';

/// Uses a WebSocket on the web, where TCP sockets are not available.
IndiTransport defaultTransport(String host, int port) =>
    WebSocketTransport(Uri(scheme: 'ws', host: host, port: port));
