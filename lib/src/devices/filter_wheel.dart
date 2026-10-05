import '../exceptions.dart';
import '../model/enums.dart';
import '../model/properties.dart';
import 'device_wrapper.dart';
import 'standard_properties.dart';

/// A filter wheel.
///
/// ```dart
/// final wheel = FilterWheel(await client.waitForDevice('Filter Simulator'));
/// await wheel.selectFilter('Ha');
/// print(wheel.currentFilter);
/// ```
///
/// {@category Device wrappers}
final class FilterWheel extends IndiDeviceWrapper {
  /// Wraps [device].
  FilterWheel(super.device);

  /// The current slot, starting at 1.
  int? get slot => numberValue(
        StandardProperties.filterSlot,
        StandardElements.filterSlotValue,
      )?.round();

  /// The current slot, now and after every change.
  Stream<int> get slotStream => watchValue<NumberProperty, int>(
        StandardProperties.filterSlot,
        (p) => p.valueOf(StandardElements.filterSlotValue)?.round(),
      );

  /// Whether the wheel is turning.
  bool get isMoving =>
      stateOf(StandardProperties.filterSlot) == PropertyState.busy;

  /// The number of slots.
  int? get slotCount {
    final max = device
        .getNumber(
            StandardProperties.filterSlot)?[StandardElements.filterSlotValue]
        ?.max;
    return max == null || max < 1 ? filterNames.length : max.round();
  }

  /// The filter names, by slot (index 0 is slot 1).
  List<String> get filterNames {
    final property = device.getText(StandardProperties.filterName);
    if (property == null) return const [];
    final bySlot = <int, String>{};
    for (final element in property.elements) {
      final slot = int.tryParse(
        element.name.replaceFirst(StandardElements.filterSlotNamePrefix, ''),
      );
      if (slot != null) bySlot[slot] = element.value;
    }
    final slots = bySlot.keys.toList()..sort();
    return [for (final slot in slots) bySlot[slot]!];
  }

  /// The name of the filter in place, if known.
  String? get currentFilter {
    final current = slot;
    final names = filterNames;
    if (current == null || current < 1 || current > names.length) return null;
    return names[current - 1];
  }

  /// Turns the wheel to [slot] (starting at 1) and completes on arrival.
  Future<void> selectSlot(int slot, {Duration? timeout}) => moveNumbers(
        StandardProperties.filterSlot,
        {StandardElements.filterSlotValue: slot},
        timeout: timeout,
      );

  /// Turns the wheel to the filter called [filterName] (ignoring case).
  ///
  /// Throws an [IndiNotFoundException] if there is no such filter.
  Future<void> selectFilter(String filterName, {Duration? timeout}) {
    final names = filterNames;
    final index =
        names.indexWhere((n) => n.toLowerCase() == filterName.toLowerCase());
    if (index < 0) {
      throw IndiNotFoundException(
        'Filter wheel "$name" has no filter "$filterName" '
        '(filters: ${names.join(', ')})',
      );
    }
    return selectSlot(index + 1, timeout: timeout);
  }

  /// Renames the filters, by slot (index 0 is slot 1).
  Future<void> setFilterNames(List<String> names) =>
      device.sendTexts(StandardProperties.filterName, {
        for (var i = 0; i < names.length; i++)
          '${StandardElements.filterSlotNamePrefix}${i + 1}': names[i],
      });
}
