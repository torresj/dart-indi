import '../model/enums.dart';
import '../model/properties.dart';
import '../protocol/number_format.dart';
import '../protocol/timestamp.dart';
import 'device_wrapper.dart';
import 'guider.dart';
import 'standard_properties.dart';
import 'values.dart';

/// A telescope mount.
///
/// ```dart
/// final mount = Telescope(await client.waitForDevice('Telescope Simulator'));
/// await mount.connect();
/// await mount.unpark();
/// await mount.slewTo(EquatorialCoordinates.parse('05:35:17', '-05:23:28'));
/// mount.coordinatesStream.listen(print);
/// ```
///
/// {@category Device wrappers}
final class Telescope extends IndiDeviceWrapper with GuiderControls {
  /// Wraps [device].
  Telescope(super.device);

  /// The property holding the current coordinates: epoch of date when the
  /// driver has it, J2000 otherwise.
  String get _coordinates =>
      device[StandardProperties.equatorialEodCoord] != null
          ? StandardProperties.equatorialEodCoord
          : StandardProperties.equatorialCoord;

  static EquatorialCoordinates? _equatorial(NumberProperty? property) {
    final ra = property?.valueOf(StandardElements.ra);
    final dec = property?.valueOf(StandardElements.dec);
    if (ra == null || dec == null) return null;
    return EquatorialCoordinates(raHours: ra, decDegrees: dec);
  }

  /// Where the mount points, or `null` if unknown.
  EquatorialCoordinates? get coordinates =>
      _equatorial(device.getNumber(_coordinates));

  /// Where the mount points, now and after every change.
  Stream<EquatorialCoordinates> get coordinatesStream =>
      watchValue<NumberProperty, EquatorialCoordinates>(
        _coordinates,
        _equatorial,
      );

  /// The target of the current or last slew, if the driver reports it.
  EquatorialCoordinates? get targetCoordinates =>
      _equatorial(device.getNumber(StandardProperties.targetEodCoord));

  /// Where the mount points in altitude and azimuth, if the driver reports
  /// it.
  HorizontalCoordinates? get horizontalCoordinates =>
      _horizontal(device.getNumber(StandardProperties.horizontalCoord));

  /// Horizontal coordinates now and after every change.
  Stream<HorizontalCoordinates> get horizontalCoordinatesStream =>
      watchValue<NumberProperty, HorizontalCoordinates>(
        StandardProperties.horizontalCoord,
        _horizontal,
      );

  static HorizontalCoordinates? _horizontal(NumberProperty? property) {
    final alt = property?.valueOf(StandardElements.alt);
    final az = property?.valueOf(StandardElements.az);
    if (alt == null || az == null) return null;
    return HorizontalCoordinates(altitudeDegrees: alt, azimuthDegrees: az);
  }

  /// Whether the mount is moving to a target.
  bool get isSlewing => stateOf(_coordinates) == PropertyState.busy;

  /// Slews to [target] and completes when the mount arrives.
  ///
  /// With [track] (the default) the mount tracks the target afterwards;
  /// otherwise it stops there. Drivers without the `ON_COORD_SET` property
  /// apply their default behavior.
  Future<void> slewTo(
    EquatorialCoordinates target, {
    bool track = true,
    Duration? timeout,
  }) async {
    if (device.getSwitch(StandardProperties.onCoordSet) != null) {
      await ensureSwitch(
        StandardProperties.onCoordSet,
        track ? StandardElements.track : StandardElements.slew,
      );
    }
    await moveNumbers(
      _coordinates,
      {
        StandardElements.ra: target.raHours,
        StandardElements.dec: target.decDegrees,
      },
      timeout: timeout,
    );
  }

  /// Tells the mount it is pointing at [coordinates], to correct its
  /// pointing model.
  Future<void> syncTo(EquatorialCoordinates coordinates) async {
    await ensureSwitch(StandardProperties.onCoordSet, StandardElements.sync);
    await device.sendNumbers(_coordinates, {
      StandardElements.ra: coordinates.raHours,
      StandardElements.dec: coordinates.decDegrees,
    });
  }

  /// Stops any motion.
  Future<void> abort() => device.setSwitch(
        StandardProperties.telescopeAbortMotion,
        StandardElements.abort,
      );

  /// Whether the mount is parked, or `null` if it can't park.
  bool? get isParked => switchValue(
        StandardProperties.telescopePark,
        StandardElements.park,
      );

  /// Parks the mount and completes when it is parked.
  Future<void> park({Duration? timeout}) => device.setSwitch(
        StandardProperties.telescopePark,
        StandardElements.park,
        timeout: timeout,
      );

  /// Unparks the mount.
  Future<void> unpark({Duration? timeout}) => device.setSwitch(
        StandardProperties.telescopePark,
        StandardElements.unpark,
        timeout: timeout,
      );

  /// Whether the mount is tracking, or `null` if unknown.
  bool? get isTracking => switchValue(
        StandardProperties.telescopeTrackState,
        StandardElements.trackOn,
      );

  /// Turns tracking on or off.
  Future<void> setTracking(bool enabled) => device.setSwitch(
        StandardProperties.telescopeTrackState,
        enabled ? StandardElements.trackOn : StandardElements.trackOff,
      );

  /// The tracking rate, or `null` if unknown.
  TrackMode? get trackMode {
    final active = device
        .getSwitch(StandardProperties.telescopeTrackMode)
        ?.activeElement
        ?.name;
    for (final mode in TrackMode.values) {
      if (mode.element == active) return mode;
    }
    return null;
  }

  /// Sets the tracking rate.
  Future<void> setTrackMode(TrackMode mode) => device.setSwitch(
        StandardProperties.telescopeTrackMode,
        mode.element,
      );

  /// The available manual slew rates. Their names depend on the driver.
  List<SwitchElement> get slewRates =>
      device.getSwitch(StandardProperties.telescopeSlewRate)?.elements ??
      const [];

  /// The name of the current manual slew rate.
  String? get slewRate => device
      .getSwitch(StandardProperties.telescopeSlewRate)
      ?.activeElement
      ?.name;

  /// Sets the manual slew rate to the element called [rate]; see
  /// [slewRates].
  Future<void> setSlewRate(String rate) =>
      device.setSwitch(StandardProperties.telescopeSlewRate, rate);

  /// Starts moving in [direction] at the manual slew rate, until
  /// [stopMotion] or [abort].
  Future<void> startMotion(GuideDirection direction) {
    final (property, element) = _motion(direction);
    return device.sendSwitches(property, {element: true});
  }

  /// Stops moving in [direction].
  Future<void> stopMotion(GuideDirection direction) {
    final (property, element) = _motion(direction);
    return device.sendSwitches(property, {element: false});
  }

  static (String, String) _motion(GuideDirection direction) =>
      switch (direction) {
        GuideDirection.north => (
            StandardProperties.telescopeMotionNs,
            StandardElements.motionNorth,
          ),
        GuideDirection.south => (
            StandardProperties.telescopeMotionNs,
            StandardElements.motionSouth,
          ),
        GuideDirection.west => (
            StandardProperties.telescopeMotionWe,
            StandardElements.motionWest,
          ),
        GuideDirection.east => (
            StandardProperties.telescopeMotionWe,
            StandardElements.motionEast,
          ),
      };

  /// The side of the pier, for German equatorial mounts.
  PierSide? get pierSide {
    final property = device.getSwitch(StandardProperties.telescopePierSide);
    if (property == null) return null;
    if (property.isOn(StandardElements.pierWest)) return PierSide.west;
    if (property.isOn(StandardElements.pierEast)) return PierSide.east;
    return null;
  }

  /// The observing site configured in the mount.
  GeographicLocation? get location {
    final property = device.getNumber(StandardProperties.geographicCoord);
    final lat = property?.valueOf(StandardElements.latitude);
    final long = property?.valueOf(StandardElements.longitude);
    if (lat == null || long == null) return null;
    return GeographicLocation(
      latitudeDegrees: lat,
      longitudeDegrees: long > 180 ? long - 360 : long,
      elevationMeters: property?.valueOf(StandardElements.elevation) ?? 0,
    );
  }

  /// Sets the observing site.
  Future<void> setLocation(GeographicLocation location) =>
      device.sendNumbers(StandardProperties.geographicCoord, {
        StandardElements.latitude: location.latitudeDegrees,
        StandardElements.longitude: location.indiLongitude,
        StandardElements.elevation: location.elevationMeters,
      });

  /// Sets the mount's clock to [time] (for example `DateTime.now()`), with
  /// the local [utcOffset] (defaults to the offset of [time]).
  Future<void> setTime(DateTime time, {Duration? utcOffset}) {
    final offset = utcOffset ?? time.timeZoneOffset;
    return device.sendTexts(StandardProperties.timeUtc, {
      StandardElements.utc: formatIndiTimestamp(time),
      StandardElements.offset: formatIndiNumber(offset.inMinutes / 60, '%.2f'),
    });
  }

  /// The aperture of the telescope in millimeters, if configured.
  double? get aperture => numberValue(
        StandardProperties.telescopeInfo,
        StandardElements.telescopeAperture,
      );

  /// The focal length of the telescope in millimeters, if configured.
  double? get focalLength => numberValue(
        StandardProperties.telescopeInfo,
        StandardElements.telescopeFocalLength,
      );
}
