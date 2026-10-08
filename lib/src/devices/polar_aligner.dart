import '../model/enums.dart';
import 'device_wrapper.dart';
import 'standard_properties.dart';
import 'values.dart';

/// A polar alignment corrector: a motorized base that moves the mount in
/// azimuth and altitude to fix its polar alignment.
///
/// {@category Device wrappers}
final class PolarAligner extends IndiDeviceWrapper {
  /// Wraps [device].
  PolarAligner(super.device);

  /// Moves the base by [azimuth] and [altitude] degrees, and completes when
  /// the motion is done. The sign sets the direction; which way is
  /// positive depends on the device and its reverse settings.
  Future<void> moveBy({
    double azimuth = 0,
    double altitude = 0,
    Duration? timeout,
  }) =>
      moveNumbers(
        StandardProperties.pacManualAdjustment,
        {
          StandardElements.manualAzStep: azimuth,
          StandardElements.manualAltStep: altitude,
        },
        timeout: timeout,
      );

  /// Whether the base is moving.
  bool get isMoving =>
      stateOf(StandardProperties.pacManualAdjustment) == PropertyState.busy;

  /// Stops the motion.
  Future<void> abort() => device.setSwitch(
        StandardProperties.pacAbortMotion,
        StandardElements.abort,
      );

  /// The position of each axis, if the device reports it.
  HorizontalCoordinates? get position {
    final property = device.getNumber(StandardProperties.pacPosition);
    final az = property?.valueOf(StandardElements.positionAz);
    final alt = property?.valueOf(StandardElements.positionAlt);
    if (az == null || alt == null) return null;
    return HorizontalCoordinates(altitudeDegrees: alt, azimuthDegrees: az);
  }

  /// The motor speed, or `null` if it can't be set.
  int? get speed =>
      numberValue(StandardProperties.pacSpeed, StandardElements.pacSpeedValue)
          ?.round();

  /// Sets the motor speed, within the range the driver reports.
  Future<void> setSpeed(int speed) => device.sendNumber(
        StandardProperties.pacSpeed,
        StandardElements.pacSpeedValue,
        speed,
      );

  /// Whether the azimuth axis is reversed, or `null` if it can't be.
  bool? get isAzimuthReversed => switchValue(
        StandardProperties.pacAzReverse,
        StandardElements.indiEnabled,
      );

  /// Reverses the azimuth axis.
  Future<void> setAzimuthReversed(bool reversed) => device.setSwitch(
        StandardProperties.pacAzReverse,
        reversed ? StandardElements.indiEnabled : StandardElements.indiDisabled,
      );

  /// Whether the altitude axis is reversed, or `null` if it can't be.
  bool? get isAltitudeReversed => switchValue(
        StandardProperties.pacAltReverse,
        StandardElements.indiEnabled,
      );

  /// Reverses the altitude axis.
  Future<void> setAltitudeReversed(bool reversed) => device.setSwitch(
        StandardProperties.pacAltReverse,
        reversed ? StandardElements.indiEnabled : StandardElements.indiDisabled,
      );
}
