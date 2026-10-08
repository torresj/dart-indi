import '../model/enums.dart';
import '../model/properties.dart';
import 'device_wrapper.dart';
import 'standard_properties.dart';

/// A field rotator.
///
/// {@category Device wrappers}
final class Rotator extends IndiDeviceWrapper {
  /// Wraps [device].
  Rotator(super.device);

  /// The angle in degrees.
  double? get angle => numberValue(
        StandardProperties.absRotatorAngle,
        StandardElements.angle,
      );

  /// The angle, now and after every change.
  Stream<double> get angleStream => watchValue<NumberProperty, double>(
        StandardProperties.absRotatorAngle,
        (p) => p.valueOf(StandardElements.angle),
      );

  /// Whether the rotator is moving.
  bool get isMoving =>
      stateOf(StandardProperties.absRotatorAngle) == PropertyState.busy;

  /// Rotates to [degrees] and completes on arrival.
  Future<void> moveTo(double degrees, {Duration? timeout}) => moveNumbers(
        StandardProperties.absRotatorAngle,
        {StandardElements.angle: degrees},
        timeout: timeout,
      );

  /// Stops the rotator.
  Future<void> abort() => device.setSwitch(
        StandardProperties.rotatorAbortMotion,
        StandardElements.abort,
      );

  /// Declares the current angle to be [degrees], without moving.
  Future<void> sync(double degrees) => device.sendNumber(
        StandardProperties.syncRotatorAngle,
        StandardElements.angle,
        degrees,
      );

  /// Whether the direction of rotation is reversed, or `null` if the
  /// driver can't reverse it.
  bool? get isReversed => switchValue(
        StandardProperties.rotatorReverse,
        StandardElements.indiEnabled,
      );

  /// Reverses the direction of rotation.
  Future<void> setReversed(bool reversed) => device.setSwitch(
        StandardProperties.rotatorReverse,
        reversed ? StandardElements.indiEnabled : StandardElements.indiDisabled,
      );
}
