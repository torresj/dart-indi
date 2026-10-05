import 'package:meta/meta.dart';

import '../protocol/number_format.dart';

/// Equatorial coordinates: right ascension and declination.
///
/// {@category Device wrappers}
@immutable
final class EquatorialCoordinates {
  /// Creates coordinates from right ascension in hours (0 to 24) and
  /// declination in degrees (-90 to 90).
  const EquatorialCoordinates({
    required this.raHours,
    required this.decDegrees,
  });

  /// Parses sexagesimal or decimal text, such as `'05:35:17'` and
  /// `'-05:23:28'`.
  ///
  /// Throws a [FormatException] if either value can't be parsed.
  factory EquatorialCoordinates.parse(String ra, String dec) {
    final raHours = parseIndiNumber(ra);
    final decDegrees = parseIndiNumber(dec);
    if (raHours == null || decDegrees == null) {
      throw FormatException('Invalid coordinates', '$ra $dec');
    }
    return EquatorialCoordinates(raHours: raHours, decDegrees: decDegrees);
  }

  /// Right ascension, in hours.
  final double raHours;

  /// Declination, in degrees.
  final double decDegrees;

  /// Right ascension, in degrees.
  double get raDegrees => raHours * 15;

  @override
  bool operator ==(Object other) =>
      other is EquatorialCoordinates &&
      other.raHours == raHours &&
      other.decDegrees == decDegrees;

  @override
  int get hashCode => Object.hash(raHours, decDegrees);

  /// Formats as `RA 05:35:17.3 DEC -05:23:28`.
  @override
  String toString() => 'RA ${_sexagesimal(raHours, 8, signed: false)} '
      'DEC ${_sexagesimal(decDegrees, 6, signed: true)}';
}

/// Sexagesimal text with the whole part zero-padded to two digits.
String _sexagesimal(double value, int fractionDigits, {required bool signed}) {
  final text = formatSexagesimal(value.abs(), fractionDigits: fractionDigits)
      .trim()
      .padLeft(fractionDigits == 8 ? 10 : 8, '0');
  final sign = value < 0 ? '-' : (signed ? '+' : '');
  return '$sign$text';
}

/// Horizontal coordinates: altitude and azimuth.
///
/// {@category Device wrappers}
@immutable
final class HorizontalCoordinates {
  /// Creates coordinates from altitude and azimuth in degrees.
  const HorizontalCoordinates({
    required this.altitudeDegrees,
    required this.azimuthDegrees,
  });

  /// Altitude above the horizon, in degrees.
  final double altitudeDegrees;

  /// Azimuth, in degrees from north through east.
  final double azimuthDegrees;

  @override
  bool operator ==(Object other) =>
      other is HorizontalCoordinates &&
      other.altitudeDegrees == altitudeDegrees &&
      other.azimuthDegrees == azimuthDegrees;

  @override
  int get hashCode => Object.hash(altitudeDegrees, azimuthDegrees);

  /// Formats as `ALT +45:00:00 AZ 180:00:00`.
  @override
  String toString() => 'ALT ${_sexagesimal(altitudeDegrees, 6, signed: true)} '
      'AZ ${_sexagesimal(azimuthDegrees, 6, signed: false)}';
}

/// An observing site.
///
/// {@category Device wrappers}
@immutable
final class GeographicLocation {
  /// Creates a location. [longitudeDegrees] is east-positive; values from
  /// -180 to 360 are accepted.
  const GeographicLocation({
    required this.latitudeDegrees,
    required this.longitudeDegrees,
    this.elevationMeters = 0,
  });

  /// Latitude in degrees, north positive.
  final double latitudeDegrees;

  /// Longitude in degrees, east positive.
  final double longitudeDegrees;

  /// Elevation above sea level, in meters.
  final double elevationMeters;

  /// The longitude as INDI expects it: 0 to 360 degrees east.
  double get indiLongitude =>
      longitudeDegrees < 0 ? longitudeDegrees + 360 : longitudeDegrees;

  @override
  bool operator ==(Object other) =>
      other is GeographicLocation &&
      other.latitudeDegrees == latitudeDegrees &&
      other.longitudeDegrees == longitudeDegrees &&
      other.elevationMeters == elevationMeters;

  @override
  int get hashCode =>
      Object.hash(latitudeDegrees, longitudeDegrees, elevationMeters);

  @override
  String toString() => 'GeographicLocation(lat: $latitudeDegrees, '
      'long: $longitudeDegrees, elev: $elevationMeters)';
}

/// A direction for guide pulses and manual motion.
///
/// {@category Device wrappers}
enum GuideDirection {
  /// North (increasing declination).
  north,

  /// South.
  south,

  /// East.
  east,

  /// West.
  west,
}

/// The side of the pier a German equatorial mount is on.
///
/// {@category Device wrappers}
enum PierSide {
  /// The telescope is west of the pier, looking east.
  west,

  /// The telescope is east of the pier, looking west.
  east,
}

/// A tracking rate.
///
/// {@category Device wrappers}
enum TrackMode {
  /// Sidereal rate, for stars.
  sidereal('TRACK_SIDEREAL'),

  /// Solar rate.
  solar('TRACK_SOLAR'),

  /// Lunar rate.
  lunar('TRACK_LUNAR'),

  /// A custom rate.
  custom('TRACK_CUSTOM');

  const TrackMode(this.element);

  /// The element name in `TELESCOPE_TRACK_MODE`.
  final String element;
}

/// The kind of frame a camera takes.
///
/// {@category Device wrappers}
enum FrameType {
  /// A normal image.
  light('FRAME_LIGHT'),

  /// A zero-length exposure, for read noise.
  bias('FRAME_BIAS'),

  /// An exposure with the shutter closed, for thermal noise.
  dark('FRAME_DARK'),

  /// An image of a uniform light source, for vignetting and dust.
  flat('FRAME_FLAT');

  const FrameType(this.element);

  /// The element name in `CCD_FRAME_TYPE`.
  final String element;
}

/// The image format a camera sends.
///
/// {@category Device wrappers}
enum TransferFormat {
  /// FITS.
  fits('FORMAT_FITS'),

  /// The camera's native format, such as a DSLR raw file.
  native('FORMAT_NATIVE'),

  /// XISF.
  xisf('FORMAT_XISF');

  const TransferFormat(this.element);

  /// The element name in `CCD_TRANSFER_FORMAT`.
  final String element;
}

/// Where a camera sends its images.
///
/// {@category Device wrappers}
enum UploadMode {
  /// To the client, as BLOBs.
  client('UPLOAD_CLIENT'),

  /// To a directory on the server.
  local('UPLOAD_LOCAL'),

  /// Both.
  both('UPLOAD_BOTH');

  const UploadMode(this.element);

  /// The element name in `UPLOAD_MODE`.
  final String element;
}

/// A rectangle of the sensor, in unbinned pixels.
///
/// {@category Device wrappers}
@immutable
final class SensorFrame {
  /// Creates a frame.
  const SensorFrame({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  /// The left edge.
  final int x;

  /// The top edge.
  final int y;

  /// The width.
  final int width;

  /// The height.
  final int height;

  @override
  bool operator ==(Object other) =>
      other is SensorFrame &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() => 'SensorFrame($x, $y, ${width}x$height)';
}

/// Information about a camera sensor.
///
/// {@category Device wrappers}
@immutable
final class SensorInfo {
  /// Creates sensor information.
  const SensorInfo({
    required this.width,
    required this.height,
    required this.pixelSizeX,
    required this.pixelSizeY,
    required this.bitsPerPixel,
  });

  /// The width in pixels.
  final int width;

  /// The height in pixels.
  final int height;

  /// The pixel width in micrometers.
  final double pixelSizeX;

  /// The pixel height in micrometers.
  final double pixelSizeY;

  /// The bit depth.
  final int bitsPerPixel;

  @override
  bool operator ==(Object other) =>
      other is SensorInfo &&
      other.width == width &&
      other.height == height &&
      other.pixelSizeX == pixelSizeX &&
      other.pixelSizeY == pixelSizeY &&
      other.bitsPerPixel == bitsPerPixel;

  @override
  int get hashCode =>
      Object.hash(width, height, pixelSizeX, pixelSizeY, bitsPerPixel);

  @override
  String toString() => 'SensorInfo(${width}x$height, '
      '${pixelSizeX}x$pixelSizeY µm, $bitsPerPixel bits)';
}
