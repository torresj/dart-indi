import '../model/enums.dart';
import '../model/properties.dart';
import 'device_wrapper.dart';
import 'standard_properties.dart';

/// The state of a dome shutter or a roll-off roof.
///
/// {@category Device wrappers}
enum ShutterState {
  /// Open.
  open,

  /// Closed.
  closed,

  /// Opening or closing.
  moving,
}

/// An observatory dome or roll-off roof.
///
/// {@category Device wrappers}
final class Dome extends IndiDeviceWrapper {
  /// Wraps [device].
  Dome(super.device);

  /// The shutter state, or `null` if the dome has no shutter.
  ShutterState? get shutterState {
    final property = device.getSwitch(StandardProperties.domeShutter);
    if (property == null) return null;
    if (property.state == PropertyState.busy) return ShutterState.moving;
    if (property.isOn(StandardElements.shutterOpen)) return ShutterState.open;
    if (property.isOn(StandardElements.shutterClose)) {
      return ShutterState.closed;
    }
    return null;
  }

  /// Opens the shutter and completes when it is open.
  Future<void> openShutter({Duration? timeout}) => device.setSwitch(
        StandardProperties.domeShutter,
        StandardElements.shutterOpen,
        timeout: timeout,
      );

  /// Closes the shutter and completes when it is closed.
  Future<void> closeShutter({Duration? timeout}) => device.setSwitch(
        StandardProperties.domeShutter,
        StandardElements.shutterClose,
        timeout: timeout,
      );

  /// The azimuth in degrees, if the dome reports it.
  double? get azimuth => numberValue(
        StandardProperties.absDomePosition,
        StandardElements.domeAbsolutePosition,
      );

  /// The azimuth, now and after every change.
  Stream<double> get azimuthStream => watchValue<NumberProperty, double>(
        StandardProperties.absDomePosition,
        (p) => p.valueOf(StandardElements.domeAbsolutePosition),
      );

  /// Whether the dome is rotating.
  bool get isMoving =>
      stateOf(StandardProperties.absDomePosition) == PropertyState.busy;

  /// Rotates to [azimuth] degrees and completes on arrival.
  Future<void> moveTo(double azimuth, {Duration? timeout}) => moveNumbers(
        StandardProperties.absDomePosition,
        {StandardElements.domeAbsolutePosition: azimuth},
        timeout: timeout,
      );

  /// Stops any motion.
  Future<void> abort() => device.setSwitch(
        StandardProperties.domeAbortMotion,
        StandardElements.abort,
      );

  /// Whether the dome is parked, or `null` if it can't park.
  bool? get isParked =>
      switchValue(StandardProperties.domePark, StandardElements.park);

  /// Parks the dome.
  Future<void> park({Duration? timeout}) => device.setSwitch(
        StandardProperties.domePark,
        StandardElements.park,
        timeout: timeout,
      );

  /// Unparks the dome.
  Future<void> unpark({Duration? timeout}) => device.setSwitch(
        StandardProperties.domePark,
        StandardElements.unpark,
        timeout: timeout,
      );

  /// Whether the dome follows the mount, or `null` if unsupported.
  bool? get isSlaved => switchValue(
        StandardProperties.domeAutosync,
        StandardElements.domeAutosyncEnable,
      );

  /// Makes the dome follow the mount, or stop following it.
  Future<void> setSlaving(bool enabled) => device.setSwitch(
        StandardProperties.domeAutosync,
        enabled
            ? StandardElements.domeAutosyncEnable
            : StandardElements.domeAutosyncDisable,
      );
}
