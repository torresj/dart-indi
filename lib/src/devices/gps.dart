import '../model/properties.dart';
import '../protocol/timestamp.dart';
import 'device_wrapper.dart';
import 'standard_properties.dart';
import 'values.dart';

/// A GPS receiver, which provides the site location and time.
///
/// {@category Device wrappers}
final class Gps extends IndiDeviceWrapper {
  /// Wraps [device].
  Gps(super.device);

  /// The location, if fixed.
  GeographicLocation? get location {
    final property = device.getNumber(StandardProperties.geographicCoord);
    return _location(property);
  }

  /// The location, now and after every change.
  Stream<GeographicLocation> get locationStream =>
      watchValue<NumberProperty, GeographicLocation>(
        StandardProperties.geographicCoord,
        _location,
      );

  static GeographicLocation? _location(NumberProperty? property) {
    final lat = property?.valueOf(StandardElements.latitude);
    final long = property?.valueOf(StandardElements.longitude);
    if (lat == null || long == null) return null;
    return GeographicLocation(
      latitudeDegrees: lat,
      longitudeDegrees: long > 180 ? long - 360 : long,
      elevationMeters: property?.valueOf(StandardElements.elevation) ?? 0,
    );
  }

  /// The UTC time reported by the receiver, if available.
  DateTime? get time => parseIndiTimestamp(
        textValue(StandardProperties.timeUtc, StandardElements.utc),
      );

  /// Asks the receiver for a fresh fix.
  Future<void> refresh() => device.setSwitch(
        StandardProperties.gpsRefresh,
        StandardElements.refresh,
      );
}
