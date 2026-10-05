# INDI Control Panel

A Flutter app built with [`package:indi`](https://pub.dev/packages/indi). It
connects to an INDI server, lists its devices and shows every property, one
tab per group, so you can control any device, like the INDI control panel of
KStars.

```sh
# On the INDI server (or any Linux machine):
indiserver indi_simulator_telescope indi_simulator_ccd indi_simulator_focus

# Here:
flutter run -d macos   # or windows, linux, android, ios, chrome
```

On the web, put a WebSocket bridge in front of indiserver and connect to its
port:

```sh
websockify 8624 localhost:7624
```

What to look at:

- `lib/src/devices_screen.dart`: device list and connection state, driven by
  `IndiClient.events` and `IndiClient.connectionStates`.
- `lib/src/property_card.dart`: a generic editor for every property type,
  driven by `IndiDevice.watch`.
- `test/widget_test.dart`: testing the UI against `FakeIndiServer`.

The platform folders are not included in the published package. Run
`flutter create .` in this folder to recreate them.
