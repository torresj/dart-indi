import '../model/properties.dart';
import 'device_wrapper.dart';
import 'standard_properties.dart';

/// A sky quality meter, which measures the brightness of the night sky.
///
/// Some drivers, such as the INDI SQM simulator, declare no interface in
/// `DRIVER_INFO`, so look for the `SKY_QUALITY` property
/// ([StandardProperties.skyQuality]) to find these devices.
///
/// {@category Device wrappers}
final class SkyQualityMeter extends IndiDeviceWrapper {
  /// Wraps [device].
  SkyQualityMeter(super.device);

  /// The sky brightness in magnitudes per square arcsecond. Higher is
  /// darker.
  double? get skyBrightness => numberValue(
        StandardProperties.skyQuality,
        StandardElements.skyBrightness,
      );

  /// The sky brightness, now and after every change.
  Stream<double> get skyBrightnessStream => watchValue<NumberProperty, double>(
        StandardProperties.skyQuality,
        (p) => p.valueOf(StandardElements.skyBrightness),
      );

  /// The sensor temperature in °C.
  double? get temperature => numberValue(
        StandardProperties.skyQuality,
        StandardElements.skyTemperature,
      );

  /// The sensor frequency in Hz.
  double? get sensorFrequency => numberValue(
        StandardProperties.skyQuality,
        StandardElements.sensorFrequency,
      );

  /// The sensor period in counts.
  double? get sensorCounts => numberValue(
        StandardProperties.skyQuality,
        StandardElements.sensorCounts,
      );

  /// The sensor period in seconds.
  double? get sensorPeriod => numberValue(
        StandardProperties.skyQuality,
        StandardElements.sensorPeriod,
      );
}
