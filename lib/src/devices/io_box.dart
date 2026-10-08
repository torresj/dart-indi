import '../model/properties.dart';
import 'device_wrapper.dart';
import 'standard_properties.dart';
import 'values.dart';

/// A device with digital inputs, digital outputs or analog inputs, such as
/// a relay box or a power controller.
///
/// Inputs and outputs are numbered from 1, as the driver names them
/// (`DIGITAL_OUTPUT_1`, …). Pulse durations are numbered from 0 in INDI
/// (`PULSE_0` belongs to output 1); the wrapper takes output numbers
/// everywhere.
///
/// {@category Device wrappers}
final class IoBox extends IndiDeviceWrapper {
  /// Wraps [device].
  IoBox(super.device);

  /// The digital inputs, by number.
  List<IoChannel> get digitalInputs => _channels(
        StandardProperties.digitalInputPrefix,
        StandardProperties.digitalInputLabels,
      );

  /// The digital outputs, by number.
  List<IoChannel> get digitalOutputs => _channels(
        StandardProperties.digitalOutputPrefix,
        StandardProperties.digitalOutputLabels,
      );

  /// The analog inputs, by number.
  List<AnalogInput> get analogInputs => [
        for (final (number, property)
            in _numbered<NumberProperty>(StandardProperties.analogInputPrefix))
          if (property.elements.isNotEmpty)
            AnalogInput(
              number: number,
              label: _label(
                StandardProperties.analogInputLabels,
                property,
              ),
              value: property.elements.first.value,
            ),
      ];

  /// Turns output [number] on or off.
  ///
  /// When the output has a [pulseDuration], turning it on makes the driver
  /// turn it off again once the pulse is over.
  Future<void> setOutput(int number, bool on, {Duration? timeout}) =>
      device.setSwitch(
        '${StandardProperties.digitalOutputPrefix}$number',
        on ? StandardElements.on : StandardElements.off,
        timeout: timeout,
      );

  /// How long output [number] stays on when turned on, or `null` if the
  /// driver has no pulse mode. Zero means it stays on.
  Duration? pulseDuration(int number) {
    final ms = numberValue(
      '${StandardProperties.pulsePrefix}${number - 1}',
      StandardElements.duration,
    );
    return ms == null ? null : Duration(milliseconds: ms.round());
  }

  /// Sets how long output [number] stays on when turned on; zero keeps it
  /// on until it is turned off.
  Future<void> setPulseDuration(int number, Duration duration) =>
      device.sendNumber(
        '${StandardProperties.pulsePrefix}${number - 1}',
        StandardElements.duration,
        duration.inMilliseconds,
      );

  List<IoChannel> _channels(String prefix, String labels) => [
        for (final (number, property) in _numbered<SwitchProperty>(prefix))
          IoChannel(
            number: number,
            label: _label(labels, property),
            isOn: property.isOn(StandardElements.on),
          ),
      ];

  /// The properties named [prefix] followed by a number, sorted by it.
  /// Other properties sharing the prefix, such as `DIGITAL_INPUT_LABELS`,
  /// are skipped.
  List<(int, P)> _numbered<P extends IndiProperty>(String prefix) {
    final found = <(int, P)>[];
    for (final property in device.properties.values) {
      if (property is! P || !property.name.startsWith(prefix)) continue;
      final number = int.tryParse(property.name.substring(prefix.length));
      if (number != null) found.add((number, property));
    }
    return found..sort((a, b) => a.$1.compareTo(b.$1));
  }

  /// The user's name for [property] from the [labels] text property, or
  /// the driver's label.
  String _label(String labels, IndiProperty property) {
    final custom = textValue(labels, property.name);
    return custom == null || custom.isEmpty ? property.label : custom;
  }
}
