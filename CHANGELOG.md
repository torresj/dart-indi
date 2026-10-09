## 0.1.5

- New `IndiClient.reconnectNow`, which makes the next reconnection attempt
  at once instead of waiting for its delay. iOS and Android suspend or cut
  the connections of an app in the background, and the waits grow while its
  attempts fail, so apps call it when they return to the foreground. The
  session resumes as usual, and the dedicated BLOB connection is retried
  too.
- The Flutter example calls it when the app returns to the foreground.

## 0.1.4

No API changes.

- The integration tests wait for the rotator and light panel simulators
  to reach their new state, which INDI 1.9.9 can report late, and print
  the driver's updates when they fail.

## 0.1.3

- New device wrappers:
  - `IoBox`, for devices with digital inputs, digital outputs and analog
    inputs, such as relay boxes: channels with their names, `setOutput`
    and pulse lengths.
  - `SkyQualityMeter`: sky brightness in mag/arcsec², plus the sensor
    temperature and readings.
  - `PolarAligner`, for polar alignment correctors: `moveBy` in azimuth
    and altitude, `abort`, speed, position and axis reversal.
- New `Rotator.isReversed`.
- New `DustCap.isMoving`, `DustCap.canAbort` and `DustCap.abort`.
- New value classes `IoChannel` and `AnalogInput`, and the standard
  property and element names for the new wrappers.

## 0.1.2

- Link the documentation site, https://dindi.torresj.es, from the package
  page and the README.

## 0.1.1

- Fix: closing a `TcpTransport` connection could wait forever when its
  input was never listened to.
- Fix: `Camera.expose` and `Camera.nextImage` now fail with
  `IndiClosedException`, instead of `IndiConnectionLostException`, when
  the client is closed while they wait.
- The dedicated BLOB connection (`separateBlobConnection`) keeps retrying
  when its first connection attempt fails, instead of giving up silently.
- New `IndiClient.isClosed`.
- New `FakeServerConnection.fail` to simulate network errors in tests.
- Test coverage raised to 99.6% of lines.

## 0.1.0

First release.

- Complete INDI 1.7 protocol: all property types, every message, sexagesimal
  number formats, BLOB policies, and the INDI 2 ping extension.
- Streaming XML parser that decodes BLOBs while they arrive.
- `IndiClient` with automatic reconnection, keep-alive pings and session
  resume.
- Awaitable commands with local validation.
- Device wrappers: `Telescope`, `Camera`, `Guider`, `Focuser`, `FilterWheel`,
  `Dome`, `Rotator`, `Weather`, `Gps`, `DustCap` and `LightBox`.
- TCP and WebSocket transports, so it runs on every platform, including the
  web.
- `FakeIndiServer` for testing applications without hardware.
