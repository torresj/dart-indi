import 'dart:typed_data';

/// zlib is not available on this platform.
Uint8List inflate(Uint8List data) => throw UnsupportedError(
      'Decompressing BLOBs is not supported on this platform; '
      'disable compression in the driver instead',
    );
