# INDI protocol notes

How the INDI protocol and the behavior of libindi and indiserver map to
this package. Read this before changing the protocol or client code.

References: the INDI white paper (protocol 1.7) by Elwood Downey, libindi's
`indiapi.h`, `indiuserio.c`, `basedevice.cpp` and `abstractbaseclient.h`, and
indiserver's `ClInfo.cpp`.

## Wire format

| Fact | Where it is handled |
|------|---------------------|
| A TCP stream (port 7624) of top-level XML elements, with no enclosing document. | `IndiXmlParser` parses incrementally from byte chunks of any size. |
| Element names are fixed, but drivers format XML freely: attributes on separate lines, values with surrounding whitespace and newlines. | The parser trims element text; the decoder trims enum values. |
| Entities: the five predefined ones plus numeric references. Drivers escape attribute text with `&apos;`. | `decodeXmlEntities`, `escapeXmlAttribute`. |
| BLOBs are base64 inside `oneBLOB`, with line breaks; images can be 100 MB. | `Base64ByteDecoder` decodes while bytes stream in, pre-sized from `enclen` (or `size` when not compressed). |
| `size` is the size once decompressed; a format ending in `.z` is zlib-compressed. `size='0'` with no content means "no data". | `OneBlob.size`, `IndiBlob.isCompressed`, `IndiBlob.decompress`. |
| One malformed element must not end the session. | The parser reports an error, skips the rest of the broken element and resynchronizes on the next top-level command name. INDI commands never nest. |

## Messages

| Fact | Where it is handled |
|------|---------------------|
| `set*Vector` attributes `state`, `timeout`, `timestamp` and `message` are optional; absent ones keep their previous values. | `applyUpdate` in `property_updates.dart`. |
| `set*Vector` may contain only the elements that changed. | `applyUpdate` keeps the other elements. |
| `oneNumber` in `setNumberVector` can carry `min`, `max` and `step` (libindi's `IUUpdateMinMax`). | `OneNumber.min/max/step`, applied by `applyUpdate`. |
| Number values can be sexagesimal (`12:30:00`, `-12 30 00`, `12;30`). | `parseIndiNumber` (libindi's `f_scansexa`). |
| Number formats are printf or the INDI `%<w>.<f>m` sexagesimal format. | `formatIndiNumber` (libindi's `numberFormat` and `fs_sexa`). |
| Timestamps are UTC without a zone suffix. | `parseIndiTimestamp`, `formatIndiTimestamp`. |
| The `message` attribute of any vector or `delProperty` is a device message (libindi's `checkMessage`). | `IndiClient._vectorMessage`. |
| `delProperty` without `name` removes the whole device. | `IndiClient._delete`. |
| A definition can arrive for an existing property (drivers redefine properties). | Replaces it and emits `PropertyUpdated`, or `PropertyRemoved` + `PropertyDefined` if the type changed. libindi ignores duplicates instead. |
| Unknown top-level elements may appear in newer protocol versions. | Decoded as `UnknownCommand` and ignored. |

## Client behavior

| Fact | Where it is handled |
|------|---------------------|
| There is no "end of definitions" marker after `getProperties`. | `waitForDevice` / `waitForProperty`; after a reconnect, a quiet period (`resumeSettleTime`) ends the resume. |
| Many drivers expect the whole vector in `new*Vector` (for example RA and DEC together). | `sendNumbers` and `sendTexts` fill in the current values of the other elements. |
| Switch rules: OneOfMany needs exactly one switch on, and drivers reset the others. | `sendSwitches` sends the full vector with one switch on for OneOfMany and AtMostOne. |
| The answer to a command is the next update of the property that is not `Busy`; `Alert` means failure. | `CommandTracker`. A periodic update may race with the answer, hence `CommandCompletion.afterBusy`. |
| indiserver only forwards BLOBs to clients that sent `enableBLOB`. | `setBlobMode`, remembered and re-sent after reconnects and when the BLOB property is defined. |
| indiserver applies an `enableBLOB` without `name` to the whole connection, not just the device. | Documented on `IndiClient.setBlobMode`. |
| With `enableBLOB Only`, a connection receives only `setBLOBVector`. | `separateBlobConnection` uses a second connection in `Only` mode. |
| indiserver 2.x answers a client's `pingRequest` with `pingReply`; older versions forward it to the drivers. | The heartbeat stops pinging after two unanswered pings, and only detects dead links on servers that answer. |
| Servers send `pingRequest` to clients on the fast-BLOB Unix socket. | The client always answers with `pingReply`. |
| indiserver disconnects clients that fall more than `-m` MB behind. | The decoder never blocks and processes data as it arrives. |
| `DRIVER_INFO.DRIVER_INTERFACE` is a bit mask of device kinds. | `DeviceInterface`, `IndiDevice.interfaces`, `IndiClient.devicesWith`. |

## Device wrappers

| Fact | Where it is handled |
|------|---------------------|
| Some drivers declare no interface: the SQM simulator reports `DRIVER_INTERFACE` 0, even once connected. | Documented on `SkyQualityMeter`: find these devices by their `SKY_QUALITY` property. |
| The output interface numbers `DIGITAL_OUTPUT_n` from 1, but its pulse lengths `PULSE_n` from 0. | `IoBox` takes output numbers everywhere and maps them to `PULSE_{n-1}`. |
| The I/O label properties share the channel prefix (`DIGITAL_INPUT_LABELS`). | `IoBox` only reads properties whose suffix is a number. |
| `PAC_MANUAL_ADJUSTMENT` is write only, yet the driver still reports `Busy` and then `Ok` around the motion. | `PolarAligner.moveBy` waits with `CommandCompletion.afterBusy`, like the other motions. |
| A dust cap can only abort when the driver defines `CAP_ABORT`. | `DustCap.canAbort`. |
