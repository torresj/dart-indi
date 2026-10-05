import 'device_wrapper.dart';
import 'standard_properties.dart';
import 'values.dart';

/// Timed guide pulses, for mounts and for cameras with an ST4 guide port.
///
/// {@category Device wrappers}
base mixin GuiderControls on IndiDeviceWrapper {
  /// Whether the driver accepts guide pulses.
  bool get canPulseGuide =>
      device.getNumber(StandardProperties.telescopeTimedGuideNs) != null;

  /// Moves the mount in [direction] at the guide rate for [duration], and
  /// completes when the pulse is done.
  Future<void> pulseGuide(
    GuideDirection direction,
    Duration duration, {
    Duration? timeout,
  }) async {
    final ms = duration.inMilliseconds;
    final (property, values) = switch (direction) {
      GuideDirection.north => (
          StandardProperties.telescopeTimedGuideNs,
          {
            StandardElements.timedGuideNorth: ms,
            StandardElements.timedGuideSouth: 0
          },
        ),
      GuideDirection.south => (
          StandardProperties.telescopeTimedGuideNs,
          {
            StandardElements.timedGuideNorth: 0,
            StandardElements.timedGuideSouth: ms
          },
        ),
      GuideDirection.west => (
          StandardProperties.telescopeTimedGuideWe,
          {
            StandardElements.timedGuideWest: ms,
            StandardElements.timedGuideEast: 0
          },
        ),
      GuideDirection.east => (
          StandardProperties.telescopeTimedGuideWe,
          {
            StandardElements.timedGuideWest: 0,
            StandardElements.timedGuideEast: ms
          },
        ),
    };
    await device.sendNumbers(
      property,
      values,
      timeout: timeout ?? duration + const Duration(seconds: 10),
    );
  }
}

/// A device that only accepts guide pulses, such as an ST4 adapter.
///
/// Mounts and cameras that accept pulses also offer
/// [GuiderControls.pulseGuide] through `Telescope` and `Camera`.
///
/// {@category Device wrappers}
final class Guider extends IndiDeviceWrapper with GuiderControls {
  /// Wraps [device].
  Guider(super.device);
}
