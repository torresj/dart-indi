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
