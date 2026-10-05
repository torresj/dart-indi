// A small command-line INDI client.
//
// It lists every device and property of a server, and if the INDI
// simulators are running, it slews the telescope and takes an image.
//
//   indiserver indi_simulator_telescope indi_simulator_ccd
//   dart run example/main.dart [host] [port]
//
// ignore_for_file: avoid_print

import 'dart:async';

import 'package:indi/indi.dart';

Future<void> main(List<String> args) async {
  final host = args.isNotEmpty ? args[0] : 'localhost';
  final port = args.length > 1 ? int.parse(args[1]) : 7624;

  final client = IndiClient(host: host, port: port);
  client.connectionStates.listen((state) => print('Connection: $state'));
  client
      .eventsOf<MessageReceived>()
      .listen((event) => print('Message: ${event.message.text}'));

  try {
    await client.connect();
  } on IndiConnectionException catch (e) {
    print('Cannot reach $host:$port: $e');
    return;
  }

  // Definitions arrive asynchronously after connecting.
  await Future<void>.delayed(const Duration(seconds: 2));
  printDevices(client);

  final mount = client.device('Telescope Simulator');
  if (mount != null) await slew(Telescope(mount));

  final camera = client.device('CCD Simulator');
  if (camera != null) await takeImage(Camera(camera));

  await client.close();
}

void printDevices(IndiClient client) {
  for (final device in client.devices.values) {
    final interfaces = device.interfaces.map((i) => i.name).join(', ');
    print('\n${device.name} [$interfaces]');
    for (final group in device.groups) {
      print('  $group');
      for (final property in device.propertiesIn(group)) {
        final values = property.elements.map(describe).join(', ');
        print('    ${property.label} (${property.state.wireValue}): $values');
      }
    }
  }
}

String describe(IndiElement element) => switch (element) {
      NumberElement() => '${element.label}=${element.formattedValue.trim()}',
      TextElement() => '${element.label}="${element.value}"',
      SwitchElement() => '${element.label}=${element.isOn ? 'On' : 'Off'}',
      LightElement() => '${element.label}=${element.state.wireValue}',
      BlobElement() => '${element.label}=<${element.blob?.bytes.length ?? 0}'
          ' bytes>',
    };

Future<void> slew(Telescope mount) async {
  await mount.connect();
  await mount.device.waitForProperty<NumberProperty>('EQUATORIAL_EOD_COORD');
  if (mount.isParked ?? false) await mount.unpark();

  final orionNebula = EquatorialCoordinates.parse('05:35:17', '-05:23:28');
  print('\nSlewing to the Orion Nebula ($orionNebula)…');
  final positions = mount.coordinatesStream.listen((c) => print('  at $c'));
  await mount.slewTo(orionNebula);
  await positions.cancel();
  print('Arrived: ${mount.coordinates}');
}

Future<void> takeImage(Camera camera) async {
  await camera.connect();
  await camera.device.waitForProperty<NumberProperty>('CCD_EXPOSURE');
  print('\nTaking a 2 second exposure…');
  final image = await camera.expose(const Duration(seconds: 2));
  print('Received a ${image.format} image of ${image.size} bytes');
}
