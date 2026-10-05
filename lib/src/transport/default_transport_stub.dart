import 'transport.dart';
import 'websocket_transport.dart';

/// Fallback for platforms with neither `dart:io` nor JS interop.
IndiTransport defaultTransport(String host, int port) =>
    WebSocketTransport(Uri(scheme: 'ws', host: host, port: port));
