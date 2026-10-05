import 'tcp_transport.dart';
import 'transport.dart';

/// Uses TCP on platforms with `dart:io`.
IndiTransport defaultTransport(String host, int port) =>
    TcpTransport(host, port: port);
