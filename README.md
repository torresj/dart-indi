# indi

[![pub package](https://img.shields.io/pub/v/indi.svg)](https://pub.dev/packages/indi)
[![CI](https://github.com/torresj/dart-indi/actions/workflows/ci.yml/badge.svg)](https://github.com/torresj/dart-indi/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/torresj/dart-indi/branch/main/graph/badge.svg)](https://codecov.io/gh/torresj/dart-indi)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A pure Dart client for [INDI](https://indilib.org), the protocol used to
control astronomy equipment: telescope mounts, cameras, focusers, filter
wheels, domes and more. Build Flutter apps (or command-line tools) that talk
to any INDI server, such as the one running on an Astroberry, StellarMate or
any Linux box with `indiserver`.

Guides and examples: **[dindi.torresj.es](https://dindi.torresj.es)**. API
reference: [pub.dev](https://pub.dev/documentation/indi/latest/).

```dart
final client = IndiClient(host: 'astroberry.local');
await client.connect();

final mount = Telescope(await client.waitForDevice('Telescope Simulator'));
await mount.connect();
await mount.slewTo(EquatorialCoordinates.parse('05:35:17', '-05:23:28'));

final camera = Camera(await client.waitForDevice('CCD Simulator'));
final image = await camera.expose(const Duration(seconds: 30));
```

## Features

- **Complete INDI 1.7 protocol**: every message type, all five property types
  (number, text, switch, light, BLOB), sexagesimal number formats, BLOB
  policies, and the INDI 2 `pingRequest`/`pingReply` extension.
- **Automatic reconnection and session resume**: when the connection drops,
  the client reconnects with exponential backoff, requests the properties
  again, restores BLOB settings and removes whatever disappeared. Your
  `IndiDevice` objects stay valid throughout.
- **Dead-link detection**: keep-alive pings detect connections that die
  silently, like a Wi-Fi drop.
- **Awaitable commands**: `await mount.slewTo(...)` completes when the driver
  reports the slew finished, and throws with the driver's message if it fails.
- **Typed device wrappers** for mounts, cameras, guiders, focusers, filter
  wheels, domes, rotators, weather stations, GPS, dust caps, light boxes,
  I/O boxes, sky quality meters and polar alignment correctors, on top of a
  fully generic API for anything else.
- **Built for Flutter**: immutable property snapshots and streams that emit
  the current value first, ready for `StreamBuilder`.
- **Fast with large images**: BLOBs are base64-decoded while they stream in
  (about 200 MB/s), without huge intermediate strings.
- **Every platform**: Android, iOS, macOS, Windows, Linux and the web (through
  a WebSocket bridge).
- **Testable**: an in-memory `FakeIndiServer` lets you test your app without
  hardware.
- Pure Dart, no native code, three small dependencies.

## Getting started

```sh
dart pub add indi      # or: flutter pub add indi
```

You need an INDI server. To try the package without hardware, run the
simulators on any Linux machine (or a Raspberry Pi):

```sh
sudo add-apt-repository ppa:mutlaqja/ppa && sudo apt install indi-bin
indiserver indi_simulator_telescope indi_simulator_ccd indi_simulator_focus
```

## Usage

### Connecting

```dart
import 'package:indi/indi.dart';

final client = IndiClient(host: '192.168.1.20'); // port defaults to 7624
await client.connect();

// Devices appear as the server defines them.
final camera = await client.waitForDevice('CCD Simulator');

// Or find devices by kind, using the interfaces their drivers declare.
final mounts = client.devicesWith(DeviceInterface.telescope);
```

`connect()` throws an `IndiConnectionException` if the server can't be
reached. Once connected, the client stays connected: see
[Reconnection](#reconnection-and-resume). Call `close()` when done.

### Devices, properties and elements

Each device has **properties** (INDI "vectors"), and each property has
**elements** with values. Properties are immutable snapshots: every update
from the driver creates a new one.

```dart
final coords = mount.getNumber('EQUATORIAL_EOD_COORD');
print(coords?.state);                     // PropertyState.ok
print(coords?['RA']?.value);              // 5.5916…
print(coords?['RA']?.formattedValue);     // "   5:35:30", using the driver's format

final connected = mount.getSwitch('CONNECTION')?.isOn('CONNECT');
```

`StandardProperties` and `StandardElements` hold the names of the
[standard INDI properties](https://indilib.org/develop/developer-manual/101-standard-properties.html).

### Watching values

`watch` emits the current snapshot and then every change, which makes it a
natural fit for Flutter:

```dart
StreamBuilder<NumberProperty>(
  stream: camera.watch<NumberProperty>('CCD_TEMPERATURE'),
  builder: (context, snapshot) => Text(
    snapshot.data?['CCD_TEMPERATURE_VALUE']?.formattedValue ?? '…',
  ),
);
```

Everything that happens is also available as a stream of sealed events:

```dart
client.events.listen((event) {
  switch (event) {
    case DeviceAdded(:final device):
      print('New device: ${device.name}');
    case PropertyUpdated(:final property):
      print('${property.name} is now ${property.state}');
    case MessageReceived(:final message):
      print('[${message.level.name}] ${message.body}');
    default:
      break;
  }
});
```

### Sending commands

Commands are checked before sending (element names, permissions, switch rules
and ranges), and the returned future completes when the driver confirms:

```dart
await mount.sendNumbers('EQUATORIAL_EOD_COORD', {'RA': 5.5, 'DEC': -5.4});
await mount.setSwitch('TELESCOPE_TRACK_STATE', 'TRACK_ON');
await camera.sendNumber('CCD_TEMPERATURE', 'CCD_TEMPERATURE_VALUE', -10);
```

- When the driver rejects a change, the property goes to the `Alert` state and
  the future fails with an `IndiPropertyAlertException` that carries the
  driver's message.
- Pass `timeout:` to limit the wait, or set `IndiClientOptions.commandTimeout`.
- `completion: CommandCompletion.sent` returns immediately, and
  `CommandCompletion.afterBusy` waits for the property to go `Busy` and back,
  which avoids mistaking a periodic update for the answer.
- Commands are **never queued or replayed** across a reconnect, because a slew
  executed minutes late could be dangerous. Sending while disconnected throws
  an `IndiNotConnectedException`.

### Device wrappers

The wrappers give standard devices meaningful, typed methods:

| Wrapper           | Highlights                                                                     |
|-------------------|--------------------------------------------------------------------------------|
| `Telescope`       | `slewTo`, `syncTo`, `abort`, `park`, tracking and rates, motion, site, time     |
| `Camera`          | `expose`, `images`, frame type, binning, ROI, cooling, gain, offset, streaming |
| `Focuser`         | `moveTo`, `moveBy`, `abort`, `sync`, temperature                               |
| `FilterWheel`     | `selectFilter('Ha')`, `selectSlot`, filter names                               |
| `Dome`            | shutter, `moveTo` azimuth, park, slaving                                       |
| `Rotator`         | `moveTo`, `sync`, `abort`, `isReversed` and `setReversed`                      |
| `Guider`          | `pulseGuide` (also available on `Telescope` and `Camera`)                      |
| `Weather`         | `isSafe`, status per parameter, readings                                       |
| `Gps`             | location and time, `refresh`                                                   |
| `DustCap`         | `open`, `close`, `isMoving`, `abort`                                           |
| `LightBox`        | light on and off, brightness                                                   |
| `IoBox`           | digital inputs and outputs with their names, analog inputs, `setOutput`, pulse mode |
| `SkyQualityMeter` | `skyBrightness` in mag/arcsec², sensor temperature and readings                |
| `PolarAligner`    | `moveBy` azimuth and altitude, `abort`, speed, position, reverse               |

```dart
final wheel = FilterWheel(await client.waitForDevice('Filter Simulator'));
await wheel.selectFilter('Ha');

final focuser = Focuser(await client.waitForDevice('Focuser Simulator'));
await focuser.moveBy(-150);

final relays = IoBox(await client.waitForDevice('Simulator IO'));
await relays.setOutput(1, true);
```

Wrappers keep no state and expose the underlying `IndiDevice` as `device`, so
driver-specific properties are always one step away.

### Images and other BLOBs

INDI servers send binary data (BLOBs), such as images, only to clients that
enable it. `Camera.expose` does this for you. With the generic API:

```dart
await camera.setBlobMode(BlobMode.also, property: 'CCD1');
camera.watch<BlobProperty>('CCD1').listen((property) {
  final blob = property['CCD1']?.blob;
  if (blob != null) File('image${blob.format}').writeAsBytesSync(blob.decompress());
});
```

For imaging apps, set `IndiClientOptions(separateBlobConnection: true)`. Images
then arrive on a second connection, so a 50 MB download never delays other
commands.

### Reconnection and resume

```dart
final client = IndiClient(
  host: 'astroberry.local',
  options: const IndiClientOptions(
    reconnect: ReconnectPolicy(maxDelay: Duration(seconds: 30)),
    heartbeat: HeartbeatOptions(interval: Duration(seconds: 10)),
  ),
);

client.connectionStates.listen((state) => print(state));
// IndiConnected → IndiReconnecting(attempt: 1, delay: 1s) → IndiConnecting → IndiConnected
client.eventsOf<SessionResumed>().listen((e) => print('Back after ${e.downtime}'));
```

When the connection drops:

1. Pending commands fail with `IndiConnectionLostException`, and devices
   report `isAvailable == false`.
2. The client reconnects with exponential backoff and jitter.
3. Properties are requested again, and BLOB settings and watched devices are
   restored.
4. Once the definitions settle, anything that was not defined again is
   removed, and a `SessionResumed` event is emitted. The same `IndiDevice`
   objects are reused.

### Flutter web

Browsers can't open TCP connections, so on the web the client connects through
a WebSocket. Put a bridge such as
[websockify](https://github.com/novnc/websockify) next to indiserver:

```sh
websockify 8624 localhost:7624
```

```dart
final client = IndiClient(host: 'astroberry.local', port: 8624); // ws:// on the web
// or explicitly, on any platform:
final ws = IndiClient.withTransport(
  WebSocketTransport(Uri.parse('wss://observatory.example.com/indi')),
);
```

### Platform setup

| Platform | What to do |
|----------|-----------|
| Android  | Add `<uses-permission android:name="android.permission.INTERNET"/>` to `AndroidManifest.xml`. |
| iOS      | Add `NSLocalNetworkUsageDescription` to `Info.plist` to reach servers on the local network. |
| macOS    | Add `com.apple.security.network.client` to `DebugProfile.entitlements` and `Release.entitlements`. |
| Web      | Use a WebSocket bridge (see above). |

### Logging

The package logs through [`package:logging`](https://pub.dev/packages/logging)
under the `indi` logger. Set the level to `Level.FINEST` to see every command
sent and received:

```dart
Logger.root.level = Level.FINEST;
Logger.root.onRecord.listen((r) => print('${r.loggerName}: ${r.message}'));
```

### Testing your app

`package:indi/testing.dart` provides `FakeIndiServer`, an in-memory server
that behaves like indiserver and its drivers:

```dart
final server = FakeIndiServer()
  ..define(const DefNumberVector(
    device: 'Focuser',
    name: 'ABS_FOCUS_POSITION',
    elements: [DefNumber(name: 'FOCUS_ABSOLUTE_POSITION', value: 1000, max: 50000)],
  ));
final client = IndiClient.withTransport(server.transport);
await client.connect();

server.update(...);          // push changes from the "driver"
server.dropConnections();    // simulate a network failure
```

### Low-level protocol access

`package:indi/protocol.dart` exposes the protocol layer: a sealed class per
INDI message, a streaming `IndiDecoder` and an `IndiEncoder`, and the number
and timestamp formats. Use it to build proxies, loggers or test tools.

## Compatibility

- INDI protocol 1.7, as implemented by indiserver 1.8 and later. Keep-alive
  pings need indiserver 2.0 or later; with older servers they are turned off
  automatically.
- Dart 3.5 or later; Flutter 3.24 or later.

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT. See [LICENSE](LICENSE).
