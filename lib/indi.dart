/// A client for the INDI protocol, used to control astronomy equipment
/// such as telescope mounts, cameras, focusers and filter wheels from Dart
/// and Flutter applications.
///
/// Start with `IndiClient`:
///
/// ```dart
/// import 'package:indi/indi.dart';
///
/// Future<void> main() async {
///   final client = IndiClient(host: 'localhost');
///   await client.connect();
///   final mount = await client.waitForDevice('Telescope Simulator');
///   await mount.connect();
///   await client.close();
/// }
/// ```
library;

export 'src/client/client_options.dart';
export 'src/client/connection_state.dart';
export 'src/client/events.dart';
export 'src/client/indi_client.dart' show DriverInfo, IndiClient, IndiDevice;
export 'src/devices/accessories.dart';
export 'src/devices/camera.dart';
export 'src/devices/device_wrapper.dart';
export 'src/devices/dome.dart';
export 'src/devices/filter_wheel.dart';
export 'src/devices/focuser.dart';
export 'src/devices/gps.dart';
export 'src/devices/guider.dart';
export 'src/devices/rotator.dart';
export 'src/devices/standard_properties.dart';
export 'src/devices/telescope.dart';
export 'src/devices/values.dart';
export 'src/devices/weather.dart';
export 'src/exceptions.dart';
export 'src/model/blob.dart';
export 'src/model/device_interface.dart';
export 'src/model/enums.dart';
export 'src/model/message.dart';
export 'src/model/properties.dart';
export 'src/protocol/number_format.dart';
export 'src/transport/tcp_transport_stub.dart'
    if (dart.library.io) 'src/transport/tcp_transport.dart';
export 'src/transport/transport.dart';
export 'src/transport/websocket_transport.dart';
