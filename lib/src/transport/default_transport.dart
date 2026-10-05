import 'default_transport_stub.dart'
    if (dart.library.io) 'default_transport_io.dart'
    if (dart.library.js_interop) 'default_transport_web.dart' as platform;
import 'transport.dart';

/// The transport used by `IndiClient(host: ..., port: ...)`: TCP where
/// sockets are available, a WebSocket to `ws://host:port` on the web.
IndiTransport defaultTransport(String host, int port) =>
    platform.defaultTransport(host, port);
