import '../model/enums.dart';
import '../model/properties.dart';
import 'device_wrapper.dart';
import 'standard_properties.dart';

/// A weather station or safety monitor.
///
/// {@category Device wrappers}
final class Weather extends IndiDeviceWrapper {
  /// Wraps [device].
  Weather(super.device);

  /// The overall safety status: `Ok` when safe, `Busy` for warnings and
  /// `Alert` when unsafe.
  PropertyState? get status => stateOf(StandardProperties.weatherStatus);

  /// The overall status, now and after every change.
  Stream<PropertyState> get statusStream =>
      watchValue<LightProperty, PropertyState>(
        StandardProperties.weatherStatus,
        (p) => p.state,
      );

  /// Whether conditions are safe.
  bool get isSafe => status == PropertyState.ok;

  /// The status of each monitored parameter, by name.
  Map<String, PropertyState> get statuses => {
        for (final light
            in device.getLight(StandardProperties.weatherStatus)?.elements ??
                const <LightElement>[])
          light.name: light.state,
      };

  /// The current readings, by element name (such as
  /// `WEATHER_TEMPERATURE`).
  Map<String, double> get parameters => {
        for (final number in device
                .getNumber(StandardProperties.weatherParameters)
                ?.elements ??
            const <NumberElement>[])
          number.name: number.value,
      };

  /// Asks the station for fresh readings.
  Future<void> refresh() => device.setSwitch(
        StandardProperties.weatherRefresh,
        StandardElements.refresh,
      );
}
