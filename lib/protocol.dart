/// Low-level access to the INDI wire protocol.
///
/// Most applications should use `package:indi/indi.dart`, which manages
/// connections, devices and properties. Import this library to build tools
/// that work directly with protocol messages, such as proxies, loggers or
/// test servers.
///
/// ```dart
/// import 'package:indi/protocol.dart';
///
/// final xml = encodeIndiCommand(const GetProperties());
/// socket.transform(const IndiDecoder()).listen(print);
/// ```
library;

export 'src/exceptions.dart' show IndiProtocolException;
export 'src/model/enums.dart';
export 'src/protocol/commands.dart';
export 'src/protocol/decoder.dart' show IndiDecoder, IndiStreamDecoder;
export 'src/protocol/encoder.dart'
    show
        IndiEncoder,
        encodeIndiCommand,
        encodeIndiCommandChunks,
        formatWireNumber;
export 'src/protocol/number_format.dart';
export 'src/protocol/timestamp.dart';
