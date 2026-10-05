/// Tools for testing applications that use `package:indi` without real
/// hardware or a running indiserver.
///
/// ```dart
/// import 'package:indi/indi.dart';
/// import 'package:indi/testing.dart';
///
/// final server = FakeIndiServer()..define(myPropertyDefinition);
/// final client = IndiClient.withTransport(server.transport);
/// ```
///
/// The protocol classes used to define properties and send updates, such as
/// `DefNumberVector` and `SetNumberVector`, are exported too.
library;

export 'protocol.dart';
export 'src/testing/fake_indi_server.dart';
export 'src/transport/in_memory_transport.dart';
