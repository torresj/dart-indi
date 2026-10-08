import '../model/enums.dart';
import 'device_wrapper.dart';
import 'standard_properties.dart';

/// A motorized dust cap.
///
/// {@category Device wrappers}
final class DustCap extends IndiDeviceWrapper {
  /// Wraps [device].
  DustCap(super.device);

  /// Whether the cap is closed (parked), or `null` if unknown.
  bool? get isClosed =>
      switchValue(StandardProperties.capPark, StandardElements.park);

  /// Closes the cap and completes when it is closed.
  Future<void> close({Duration? timeout}) => device.setSwitch(
        StandardProperties.capPark,
        StandardElements.park,
        timeout: timeout,
      );

  /// Opens the cap and completes when it is open.
  Future<void> open({Duration? timeout}) => device.setSwitch(
        StandardProperties.capPark,
        StandardElements.unpark,
        timeout: timeout,
      );

  /// Whether the cap is opening or closing.
  bool get isMoving =>
      stateOf(StandardProperties.capPark) == PropertyState.busy;

  /// Whether the driver can stop the cap while it moves.
  bool get canAbort => device.getSwitch(StandardProperties.capAbort) != null;

  /// Stops the cap. Only drivers where [canAbort] is true support it.
  Future<void> abort() => device.setSwitch(
        StandardProperties.capAbort,
        StandardElements.abort,
      );
}

/// A light box or flat panel, for taking flat frames.
///
/// {@category Device wrappers}
final class LightBox extends IndiDeviceWrapper {
  /// Wraps [device].
  LightBox(super.device);

  /// Whether the light is on, or `null` if unknown.
  bool? get isOn => switchValue(
        StandardProperties.flatLightControl,
        StandardElements.flatLightOn,
      );

  /// Turns the light on or off.
  Future<void> setLight(bool on) => device.setSwitch(
        StandardProperties.flatLightControl,
        on ? StandardElements.flatLightOn : StandardElements.flatLightOff,
      );

  /// The brightness, if the panel can be dimmed.
  double? get brightness => numberValue(
        StandardProperties.flatLightIntensity,
        StandardElements.flatLightIntensityValue,
      );

  /// Sets the brightness, within the range the driver reports.
  Future<void> setBrightness(num value) => device.sendNumber(
        StandardProperties.flatLightIntensity,
        StandardElements.flatLightIntensityValue,
        value,
      );
}
