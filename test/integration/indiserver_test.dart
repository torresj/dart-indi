// End-to-end tests against a real indiserver running the INDI simulators.
//
// They start indiserver themselves, so they can also kill and restart it to
// test reconnection. They are skipped when indiserver is not installed; on
// Ubuntu install it with:
//
//   sudo add-apt-repository ppa:mutlaqja/ppa && sudo apt install indi-bin
@Tags(['integration'])
@TestOn('vm')
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:indi/indi.dart';
import 'package:test/test.dart';

const int port = 17624;
const int webSocketPort = 18624;
const List<String> drivers = [
  'indi_simulator_telescope',
  'indi_simulator_ccd',
  'indi_simulator_focus',
  'indi_simulator_wheel',
];

/// Simulators for the accessory wrappers. Older INDI releases lack some of
/// them (INDI 1.9 has no I/O or PAC simulator), so each one runs, and is
/// tested, only when installed.
const List<String> accessoryDrivers = [
  'indi_simulator_rotator',
  'indi_simulator_dustcover',
  'indi_simulator_lightpanel',
  'indi_simulator_sqm',
  'indi_simulator_io',
  'indi_simulator_pac',
];

final bool hasIndiServer = _onPath('indiserver');
final bool hasWebsockify = _onPath('websockify');
final List<String> installedAccessories =
    accessoryDrivers.where(_onPath).toList();

/// A skip reason when [driver] is not installed.
Object _needs(String driver) =>
    installedAccessories.contains(driver) ? false : '$driver is not installed';

bool _onPath(String executable) {
  try {
    return Process.runSync('which', [executable]).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

Future<Process> startServer() async {
  final process = await Process.start(
    'indiserver',
    ['-p', '$port', ...drivers, ...installedAccessories],
  );
  process.stderr.transform(utf8.decoder).listen((line) {
    if (Platform.environment['INDI_VERBOSE'] != null) stderr.write(line);
  });
  // Wait until the port accepts connections.
  for (var i = 0; i < 100; i++) {
    try {
      final socket = await Socket.connect('localhost', port);
      socket.destroy();
      return process;
    } on SocketException {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
  process.kill();
  throw StateError('indiserver did not start');
}

Future<void> stopServer(Process process) async {
  process.kill(ProcessSignal.sigkill);
  await process.exitCode;
}

void main() {
  group(
    'indiserver',
    _tests,
    skip: hasIndiServer ? false : 'indiserver is not installed',
  );
}

void _tests() {
  late Process server;
  late IndiClient client;

  setUp(() async {
    server = await startServer();
    client = IndiClient(
      port: port,
      options: const IndiClientOptions(
        reconnect: ReconnectPolicy(
          initialDelay: Duration(milliseconds: 200),
          maxDelay: Duration(seconds: 1),
        ),
        separateBlobConnection: true,
      ),
    );
    await client.connect();
  });

  tearDown(() async {
    await client.close();
    await stopServer(server);
  });

  test('discovers the simulators and their interfaces', () async {
    final mount = await client.waitForDevice('Telescope Simulator');
    await mount.waitForProperty<TextProperty>('DRIVER_INFO');
    expect(mount.hasInterface(DeviceInterface.telescope), isTrue);
    final camera = await client.waitForDevice('CCD Simulator');
    await camera.waitForProperty<TextProperty>('DRIVER_INFO');
    expect(camera.hasInterface(DeviceInterface.ccd), isTrue);
    expect(await client.ping(), lessThan(const Duration(seconds: 1)));
  });

  test('slews the mount', () async {
    final mount = Telescope(await client.waitForDevice('Telescope Simulator'));
    // Record what the driver reports, to explain a failure.
    final history = <String>[];
    final recording = mount.device.events.listen((event) {
      switch (event) {
        case PropertyEvent(:final property)
            when property.name == 'EQUATORIAL_EOD_COORD':
          final values = property.elements
              .map((e) => '${e.name}=${(e as NumberElement).value}')
              .join(' ');
          history.add('${event.runtimeType} ${property.state.name} $values');
        case MessageReceived(:final message):
          history.add('message: ${message.text}');
        default:
          break;
      }
    });
    addTearDown(recording.cancel);
    printOnFailure('History:');
    addTearDown(() => printOnFailure(history.join('\n')));

    await mount.connect();
    // The simulator reports real coordinates only from its first poll on;
    // until then the property holds placeholders. Wait for that first
    // update before commanding the mount, as an application should. A
    // parked simulator doesn't poll, hence the fallback.
    await mount.device
        .eventsOf<PropertyUpdated>()
        .firstWhere((e) => e.property.name == 'EQUATORIAL_EOD_COORD')
        .then<void>((_) {})
        .timeout(const Duration(seconds: 5), onTimeout: () {});
    await mount.device.waitForProperty<SwitchProperty>('TELESCOPE_PARK');
    if (mount.isParked ?? false) await mount.unpark();
    final start = mount.coordinates!;
    final target = EquatorialCoordinates(
      raHours: (start.raHours + 0.2) % 24,
      decDegrees: start.decDegrees.clamp(-80, 80) + 2,
    );
    await mount.slewTo(target, timeout: const Duration(minutes: 2));
    final end = mount.coordinates!;
    expect(end.raHours, closeTo(target.raHours, 0.01));
    expect(end.decDegrees, closeTo(target.decDegrees, 0.1));
  });

  test('takes an image', () async {
    final camera = Camera(await client.waitForDevice('CCD Simulator'));
    await camera.connect();
    await camera.device.waitForProperty<NumberProperty>('CCD_EXPOSURE');
    final image = await camera.expose(const Duration(seconds: 1));
    final data = image.decompress();
    expect(ascii.decode(data.sublist(0, 6)), 'SIMPLE');
    expect(data.length, greaterThan(100000));
  });

  test('moves the focuser and the filter wheel', () async {
    final focuser = Focuser(await client.waitForDevice('Focuser Simulator'));
    await focuser.connect();
    await focuser.device.waitForProperty<NumberProperty>('ABS_FOCUS_POSITION');
    final target = (focuser.position ?? 0) + 100;
    await focuser.moveTo(target, timeout: const Duration(minutes: 1));
    expect(focuser.position, target);

    final wheel = FilterWheel(await client.waitForDevice('Filter Simulator'));
    await wheel.connect();
    await wheel.device.waitForProperty<NumberProperty>('FILTER_SLOT');
    final slot = wheel.slot == 2 ? 3 : 2;
    await wheel.selectSlot(slot, timeout: const Duration(minutes: 1));
    expect(wheel.slot, slot);
  });

  test(
    'moves the rotator',
    () async {
      final rotator = Rotator(await client.waitForDevice('Rotator Simulator'));
      await rotator.connect();
      await rotator.device.waitForProperty<NumberProperty>('ABS_ROTATOR_ANGLE');
      final target = ((rotator.angle ?? 0) + 10) % 360;
      await rotator.moveTo(target, timeout: const Duration(minutes: 1));
      expect(rotator.angle, closeTo(target, 0.01));
    },
    skip: _needs('indi_simulator_rotator'),
  );

  test(
    'closes and opens the dust cover',
    () async {
      final cap = DustCap(await client.waitForDevice('Dust Cover Simulator'));
      await cap.connect();
      await cap.device.waitForProperty<SwitchProperty>('CAP_PARK');
      await cap.close(timeout: const Duration(minutes: 1));
      expect(cap.isClosed, isTrue);
      await cap.open(timeout: const Duration(minutes: 1));
      expect(cap.isClosed, isFalse);
    },
    skip: _needs('indi_simulator_dustcover'),
  );

  test(
    'lights the light panel',
    () async {
      final light =
          LightBox(await client.waitForDevice('Light Panel Simulator'));
      // Record what the driver reports, to explain a failure.
      final history = <String>[];
      final recording = light.device.events.listen((event) {
        if (event case PropertyEvent(:final SwitchProperty property)
            when property.name == 'FLAT_LIGHT_CONTROL') {
          history.add('${event.runtimeType} ${property.state.name} '
              'on=${property.isOn('FLAT_LIGHT_ON')}');
        }
      });
      addTearDown(recording.cancel);
      addTearDown(() => printOnFailure(history.join('\n')));

      await light.connect();
      await light.device
          .waitForProperty<NumberProperty>('FLAT_LIGHT_INTENSITY');
      await light.setLight(true);
      await light.setBrightness(128);
      expect(light.isOn, isTrue);
      expect(light.brightness, 128);
      await light.setLight(false);
      await light.device
          .watch<SwitchProperty>('FLAT_LIGHT_CONTROL')
          .firstWhere((p) => !p.isOn('FLAT_LIGHT_ON'))
          .timeout(const Duration(seconds: 10));
      expect(light.isOn, isFalse);
    },
    skip: _needs('indi_simulator_lightpanel'),
  );

  test(
    'reads the sky quality meter',
    () async {
      final sqm = SkyQualityMeter(await client.waitForDevice('SQM Simulator'));
      await sqm.connect();
      await sqm.device.waitForProperty<NumberProperty>('SKY_QUALITY');
      expect(sqm.skyBrightness, isNotNull);
    },
    skip: _needs('indi_simulator_sqm'),
  );

  test(
    'switches an output',
    () async {
      final io = IoBox(await client.waitForDevice('Simulator IO'));
      await io.connect();
      await io.device.waitForProperty<SwitchProperty>('DIGITAL_OUTPUT_1');
      expect(io.digitalInputs, isNotEmpty);
      await io.setOutput(1, true);
      expect(io.digitalOutputs.first.isOn, isTrue);
      await io.setOutput(1, false);
      expect(io.digitalOutputs.first.isOn, isFalse);
    },
    skip: _needs('indi_simulator_io'),
  );

  test(
    'moves the polar alignment corrector',
    () async {
      final pac = PolarAligner(
        await client.waitForDevice('Alignment Correction Simulator'),
      );
      await pac.connect();
      await pac.device.waitForProperty<NumberProperty>('PAC_MANUAL_ADJUSTMENT');
      // The property is write only, but the driver still reports Busy and
      // then Ok, which is what moveBy waits for.
      await pac.moveBy(azimuth: 0.1, timeout: const Duration(minutes: 1));
      expect(pac.isMoving, isFalse);
    },
    skip: _needs('indi_simulator_pac'),
  );

  test('reconnects and resumes after indiserver restarts', () async {
    final mount = await client.waitForDevice('Telescope Simulator');
    await mount.waitForProperty<SwitchProperty>('CONNECTION');
    final resumed = client.eventsOf<SessionResumed>().first;
    await stopServer(server);
    await client.connectionStates.firstWhere((s) => s is IndiReconnecting);
    expect(mount.isAvailable, isFalse);
    server = await startServer();
    final event = await resumed.timeout(const Duration(seconds: 30));
    expect(client.device('Telescope Simulator'), same(mount));
    expect(mount.isAvailable, isTrue);
    expect(event.devices, contains(mount));
  });

  test(
    'works through a WebSocket bridge',
    () async {
      final bridge = await Process.start(
        'websockify',
        ['$webSocketPort', 'localhost:$port'],
      );
      addTearDown(bridge.kill);
      await Future<void>.delayed(const Duration(seconds: 1));
      final webClient = IndiClient.withTransport(
        WebSocketTransport(Uri.parse('ws://localhost:$webSocketPort')),
      );
      addTearDown(webClient.close);
      await webClient.connect();
      final mount = await webClient.waitForDevice('Telescope Simulator');
      expect(mount.isAvailable, isTrue);
    },
    skip: hasWebsockify ? false : 'websockify is not installed',
  );
}
