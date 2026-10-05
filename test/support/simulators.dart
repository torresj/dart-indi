import 'dart:async';

import 'package:indi/indi.dart';
import 'package:indi/testing.dart';
import 'package:test/test.dart';

const String mountName = 'Telescope Simulator';
const String cameraName = 'CCD Simulator';

/// Fast timings so reconnection tests run quickly.
const IndiClientOptions fastOptions = IndiClientOptions(
  reconnect: ReconnectPolicy(
    initialDelay: Duration(milliseconds: 10),
    maxDelay: Duration(milliseconds: 50),
    jitter: 0,
  ),
  heartbeat: HeartbeatOptions.disabled(),
  resumeSettleTime: Duration(milliseconds: 50),
  resumeMaxSettleTime: Duration(milliseconds: 500),
);

DefSwitchVector connection(String device) => DefSwitchVector(
      device: device,
      name: 'CONNECTION',
      label: 'Connection',
      group: 'Main Control',
      rule: SwitchRule.oneOfMany,
      elements: const [
        DefSwitch(name: 'CONNECT', label: 'Connect', state: SwitchState.off),
        DefSwitch(
          name: 'DISCONNECT',
          label: 'Disconnect',
          state: SwitchState.on,
        ),
      ],
    );

DefTextVector driverInfo(String device, String exec, int interfaces) =>
    DefTextVector(
      device: device,
      name: 'DRIVER_INFO',
      group: 'General Info',
      perm: PropertyPermission.readOnly,
      elements: [
        DefText(name: 'DRIVER_NAME', value: device),
        DefText(name: 'DRIVER_EXEC', value: exec),
        const DefText(name: 'DRIVER_VERSION', value: '1.0'),
        DefText(name: 'DRIVER_INTERFACE', value: '$interfaces'),
      ],
    );

/// Defines a minimal mount: connection, driver info, coordinates, park,
/// tracking and a status light.
void defineMount(FakeIndiServer server) {
  server
    ..define(connection(mountName))
    ..define(driverInfo(
      mountName,
      'indi_simulator_telescope',
      DeviceInterface.telescope.mask | DeviceInterface.guider.mask,
    ))
    ..define(const DefNumberVector(
      device: mountName,
      name: 'EQUATORIAL_EOD_COORD',
      label: 'Eq. Coordinates',
      group: 'Main Control',
      timeout: 60,
      elements: [
        DefNumber(
          name: 'RA',
          label: 'RA (hh:mm:ss)',
          format: '%010.6m',
          min: 0,
          max: 24,
          value: 5.5,
        ),
        DefNumber(
          name: 'DEC',
          label: 'DEC (dd:mm:ss)',
          format: '%010.6m',
          min: -90,
          max: 90,
          value: -5.25,
        ),
      ],
    ))
    ..define(const DefSwitchVector(
      device: mountName,
      name: 'TELESCOPE_TRACK_STATE',
      group: 'Main Control',
      rule: SwitchRule.oneOfMany,
      elements: [
        DefSwitch(name: 'TRACK_ON', state: SwitchState.off),
        DefSwitch(name: 'TRACK_OFF', state: SwitchState.on),
      ],
    ))
    ..define(const DefTextVector(
      device: mountName,
      name: 'DEVICE_PORT',
      group: 'Options',
      elements: [DefText(name: 'PORT', value: '/dev/ttyUSB0')],
    ))
    ..define(const DefLightVector(
      device: mountName,
      name: 'STATUS',
      group: 'Main Control',
      elements: [DefLight(name: 'TRACKING', state: PropertyState.idle)],
    ));
}

/// Defines a minimal camera: connection, driver info, exposure,
/// temperature, frame type and the image BLOB.
void defineCamera(FakeIndiServer server) {
  server
    ..define(connection(cameraName))
    ..define(driverInfo(
      cameraName,
      'indi_simulator_ccd',
      DeviceInterface.ccd.mask | DeviceInterface.guider.mask,
    ))
    ..define(const DefNumberVector(
      device: cameraName,
      name: 'CCD_EXPOSURE',
      group: 'Main Control',
      elements: [
        DefNumber(
          name: 'CCD_EXPOSURE_VALUE',
          format: '%5.2f',
          min: 0.001,
          max: 3600,
          step: 1,
          value: 1,
        ),
      ],
    ))
    ..define(const DefNumberVector(
      device: cameraName,
      name: 'CCD_TEMPERATURE',
      group: 'Main Control',
      elements: [
        DefNumber(
          name: 'CCD_TEMPERATURE_VALUE',
          format: '%5.2f',
          min: -50,
          max: 50,
          step: 0,
          value: 20,
        ),
      ],
    ))
    ..define(const DefSwitchVector(
      device: cameraName,
      name: 'CCD_FRAME_TYPE',
      group: 'Image Settings',
      rule: SwitchRule.oneOfMany,
      elements: [
        DefSwitch(name: 'FRAME_LIGHT', state: SwitchState.on),
        DefSwitch(name: 'FRAME_BIAS', state: SwitchState.off),
        DefSwitch(name: 'FRAME_DARK', state: SwitchState.off),
        DefSwitch(name: 'FRAME_FLAT', state: SwitchState.off),
      ],
    ))
    ..define(const DefBlobVector(
      device: cameraName,
      name: 'CCD1',
      group: 'Image Info',
      elements: [DefBlob(name: 'CCD1')],
    ));
}

/// Waits until [condition] holds, polling the event loop.
Future<void> eventually(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

/// Collects the commands the server receives.
List<IndiCommand> recordReceived(FakeIndiServer server) {
  final received = <IndiCommand>[];
  server.received.listen(received.add);
  return received;
}

/// Collects the events of [client].
List<IndiEvent> recordEvents(IndiClient client) {
  final events = <IndiEvent>[];
  client.events.listen(events.add);
  return events;
}

/// Connects [client] and waits until the mount and the camera are fully
/// defined (their last properties arrived).
Future<(IndiDevice mount, IndiDevice camera)> connectAndSync(
  IndiClient client,
) async {
  if (!client.isConnected) await client.connect();
  final mount = await client.waitForDevice(mountName);
  await mount.waitForProperty<LightProperty>('STATUS');
  final camera = await client.waitForDevice(cameraName);
  await camera.waitForProperty<BlobProperty>('CCD1');
  return (mount, camera);
}
