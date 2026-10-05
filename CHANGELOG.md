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
