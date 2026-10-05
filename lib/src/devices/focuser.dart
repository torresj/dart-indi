import '../model/enums.dart';
import '../model/properties.dart';
import 'device_wrapper.dart';
import 'standard_properties.dart';

/// A focuser.
///
/// ```dart
/// final focuser = Focuser(await client.waitForDevice('Focuser Simulator'));
/// await focuser.moveTo(25000);
/// await focuser.moveBy(-100);
/// ```
///
/// {@category Device wrappers}
final class Focuser extends IndiDeviceWrapper {
  /// Wraps [device].
  Focuser(super.device);

  /// The absolute position in steps, if the focuser reports it.
  int? get position => numberValue(
        StandardProperties.absFocusPosition,
        StandardElements.focusAbsolutePosition,
      )?.round();

  /// The position, now and after every change.
  Stream<int> get positionStream => watchValue<NumberProperty, int>(
        StandardProperties.absFocusPosition,
        (p) => p.valueOf(StandardElements.focusAbsolutePosition)?.round(),
      );

  /// Whether the focuser is moving.
  bool get isMoving =>
      stateOf(StandardProperties.absFocusPosition) == PropertyState.busy ||
      stateOf(StandardProperties.relFocusPosition) == PropertyState.busy;

  /// The maximum position, if reported.
  int? get maxPosition => numberValue(
        StandardProperties.focusMax,
        StandardElements.focusMaxValue,
      )?.round();

  /// The temperature in °C, if the focuser has a sensor.
  double? get temperature => numberValue(
        StandardProperties.focusTemperature,
        StandardElements.temperature,
      );

  /// Moves to the absolute [position] and completes on arrival.
  Future<void> moveTo(int position, {Duration? timeout}) => moveNumbers(
        StandardProperties.absFocusPosition,
        {StandardElements.focusAbsolutePosition: position},
        timeout: timeout,
      );

  /// Moves by [steps]: outward when positive, inward when negative.
  /// Completes when the move ends.
  Future<void> moveBy(int steps, {Duration? timeout}) async {
    if (steps == 0) return;
    await ensureSwitch(
      StandardProperties.focusMotion,
      steps > 0 ? StandardElements.focusOutward : StandardElements.focusInward,
    );
    await device.sendNumber(
      StandardProperties.relFocusPosition,
      StandardElements.focusRelativePosition,
      steps.abs(),
      timeout: timeout,
    );
  }

  /// Stops the focuser.
  Future<void> abort() => device.setSwitch(
        StandardProperties.focusAbortMotion,
        StandardElements.abort,
      );

  /// Declares the current position to be [position], without moving.
  Future<void> sync(int position) => device.sendNumber(
        StandardProperties.focusSync,
        StandardElements.focusSyncValue,
        position,
      );

  /// Sets the speed.
  Future<void> setSpeed(int speed) => device.sendNumber(
        StandardProperties.focusSpeed,
        StandardElements.focusSpeedValue,
        speed,
      );

  /// Reverses the direction of motion, for focusers mounted the other way.
  Future<void> setReversed(bool reversed) => device.setSwitch(
        StandardProperties.focusReverseMotion,
        reversed ? StandardElements.indiEnabled : StandardElements.indiDisabled,
      );
}
