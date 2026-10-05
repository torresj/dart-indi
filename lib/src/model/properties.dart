import 'package:meta/meta.dart';

import '../exceptions.dart';
import '../protocol/number_format.dart';
import '../util/equality.dart';
import 'blob.dart';
import 'enums.dart';

mixin _Fields {
  Map<String, Object?> get _fields;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _Fields &&
          other.runtimeType == runtimeType &&
          deepEquals(_fields.values.toList(), other._fields.values.toList());

  @override
  int get hashCode =>
      Object.hash(runtimeType, deepHash(_fields.values.toList()));

  @override
  String toString() {
    final fields = _fields.entries
        .where((e) => e.value != null)
        .map((e) => '${e.key}: ${describeValue(e.value)}')
        .join(', ');
    return '$runtimeType($fields)';
  }
}

// ---------------------------------------------------------------------------
// Elements.
// ---------------------------------------------------------------------------

/// One value inside an [IndiProperty], such as the `RA` number of the
/// `EQUATORIAL_EOD_COORD` property. INDI calls these "elements" or
/// "members".
///
/// Elements are immutable snapshots; a new instance is created on every
/// update.
///
/// {@category Model}
@immutable
sealed class IndiElement with _Fields {
  const IndiElement({required this.name, required this.label});

  /// The element name, unique within its property.
  final String name;

  /// A human readable label. Equals [name] when the driver sent none.
  final String label;
}

/// A number element.
///
/// {@category Model}
final class NumberElement extends IndiElement {
  /// Creates a number element.
  const NumberElement({
    required super.name,
    String? label,
    required this.value,
    this.min = 0,
    this.max = 0,
    this.step = 0,
    this.format = '%g',
  }) : super(label: label ?? name);

  /// The current value.
  final double value;

  /// The minimum allowed value. The range is unbounded when [min] equals
  /// [max]; see [hasRange].
  final double min;

  /// The maximum allowed value.
  final double max;

  /// The step between allowed values, or 0 for any value.
  final double step;

  /// The printf-style display format, possibly sexagesimal (`%010.6m`).
  final String format;

  /// Whether [min] and [max] define a range.
  bool get hasRange => min < max;

  /// [value] formatted for display with [format], for example `12:30:00`
  /// for a right ascension.
  String get formattedValue => formatIndiNumber(value, format);

  @override
  Map<String, Object?> get _fields => {
        'name': name,
        'label': label,
        'value': value,
        'min': min,
        'max': max,
        'step': step,
        'format': format,
      };
}

/// A text element.
///
/// {@category Model}
final class TextElement extends IndiElement {
  /// Creates a text element.
  const TextElement({required super.name, String? label, this.value = ''})
      : super(label: label ?? name);

  /// The current text.
  final String value;

  @override
  Map<String, Object?> get _fields =>
      {'name': name, 'label': label, 'value': value};
}

/// A switch element.
///
/// {@category Model}
final class SwitchElement extends IndiElement {
  /// Creates a switch element.
  const SwitchElement({required super.name, String? label, required this.state})
      : super(label: label ?? name);

  /// The current state.
  final SwitchState state;

  /// Whether the switch is on.
  bool get isOn => state == SwitchState.on;

  @override
  Map<String, Object?> get _fields =>
      {'name': name, 'label': label, 'state': state};
}

/// A light element: a read-only status indicator.
///
/// {@category Model}
final class LightElement extends IndiElement {
  /// Creates a light element.
  const LightElement({required super.name, String? label, required this.state})
      : super(label: label ?? name);

  /// The current status.
  final PropertyState state;

  @override
  Map<String, Object?> get _fields =>
      {'name': name, 'label': label, 'state': state};
}

/// A BLOB element: binary data such as an image.
///
/// {@category Model}
final class BlobElement extends IndiElement {
  /// Creates a BLOB element.
  const BlobElement({required super.name, String? label, this.blob})
      : super(label: label ?? name);

  /// The last data received, or `null` if none arrived yet.
  ///
  /// The server only sends BLOBs after they are enabled with
  /// `IndiDevice.setBlobMode`.
  final IndiBlob? blob;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BlobElement &&
          other.name == name &&
          other.label == label &&
          identical(other.blob, blob);

  @override
  int get hashCode => Object.hash(name, label, blob);

  @override
  Map<String, Object?> get _fields =>
      {'name': name, 'label': label, 'blob': blob};
}

// ---------------------------------------------------------------------------
// Properties.
// ---------------------------------------------------------------------------

/// A named group of values of a device, such as `EQUATORIAL_EOD_COORD`
/// (right ascension and declination) or `CONNECTION`. INDI calls these
/// "properties" or "vectors".
///
/// Properties are immutable snapshots: every update from the driver
/// produces a new instance, which makes them easy to use with Flutter's
/// `StreamBuilder`. Use `IndiDevice.watch` to follow a property over time.
///
/// {@category Model}
@immutable
sealed class IndiProperty<E extends IndiElement> with _Fields {
  IndiProperty({
    required this.device,
    required this.name,
    String? label,
    this.group = '',
    this.state = PropertyState.idle,
    this.permission = PropertyPermission.readWrite,
    this.timeout = 0,
    this.timestamp,
    required List<E> elements,
  })  : label = label ?? name,
        elements = List.unmodifiable(elements);

  /// The name of the device that owns the property.
  final String device;

  /// The property name, unique within the device.
  final String name;

  /// A human readable label. Equals [name] when the driver sent none.
  final String label;

  /// The group used to organize properties in user interfaces, such as
  /// `Main Control`.
  final String group;

  /// The current state.
  final PropertyState state;

  /// Whether the client may read and write the property.
  final PropertyPermission permission;

  /// The worst-case time, in seconds, the driver needs to apply a change.
  final double timeout;

  /// When the driver last changed the property, if it said so.
  final DateTime? timestamp;

  /// The elements, in the order the driver defined them.
  final List<E> elements;

  late final Map<String, E> _byName = {
    for (final element in elements) element.name: element,
  };

  /// The type of the property.
  PropertyType get type;

  /// The element called [elementName], or `null` if there is none.
  E? operator [](String elementName) => _byName[elementName];

  /// The element called [elementName].
  ///
  /// Throws an [IndiNotFoundException] if there is none.
  E element(String elementName) =>
      _byName[elementName] ??
      (throw IndiNotFoundException(
        'Property "$device.$name" has no element "$elementName"',
      ));

  /// The names of the elements, in order.
  Iterable<String> get elementNames => elements.map((e) => e.name);

  /// Whether the property is in the `Busy` state.
  bool get isBusy => state == PropertyState.busy;

  Map<String, Object?> get _propertyFields => {
        'device': device,
        'name': name,
        'label': label,
        'group': group,
        'state': state,
        'permission': permission,
        'timeout': timeout,
        'timestamp': timestamp,
        'elements': elements,
      };

  @override
  Map<String, Object?> get _fields => _propertyFields;
}

/// A property made of numbers, such as coordinates or a temperature.
///
/// {@category Model}
final class NumberProperty extends IndiProperty<NumberElement> {
  /// Creates a number property.
  NumberProperty({
    required super.device,
    required super.name,
    super.label,
    super.group,
    super.state,
    super.permission,
    super.timeout,
    super.timestamp,
    required super.elements,
  });

  @override
  PropertyType get type => PropertyType.number;

  /// The value of the element called [elementName], or `null` if there is
  /// none.
  double? valueOf(String elementName) => this[elementName]?.value;
}

/// A property made of texts, such as a device port or driver information.
///
/// {@category Model}
final class TextProperty extends IndiProperty<TextElement> {
  /// Creates a text property.
  TextProperty({
    required super.device,
    required super.name,
    super.label,
    super.group,
    super.state,
    super.permission,
    super.timeout,
    super.timestamp,
    required super.elements,
  });

  @override
  PropertyType get type => PropertyType.text;

  /// The text of the element called [elementName], or `null` if there is
  /// none.
  String? valueOf(String elementName) => this[elementName]?.value;
}

/// A property made of switches, such as `CONNECTION` or a list of modes.
///
/// {@category Model}
final class SwitchProperty extends IndiProperty<SwitchElement> {
  /// Creates a switch property.
  SwitchProperty({
    required super.device,
    required super.name,
    super.label,
    super.group,
    super.state,
    super.permission,
    super.timeout,
    super.timestamp,
    this.rule = SwitchRule.anyOfMany,
    required super.elements,
  });

  /// The rule that constrains which switches can be on.
  final SwitchRule rule;

  @override
  PropertyType get type => PropertyType.switches;

  /// The switches that are on.
  Iterable<SwitchElement> get activeElements => elements.where((e) => e.isOn);

  /// The first switch that is on, or `null` if all are off. Convenient for
  /// [SwitchRule.oneOfMany] and [SwitchRule.atMostOne] properties.
  SwitchElement? get activeElement {
    for (final element in elements) {
      if (element.isOn) return element;
    }
    return null;
  }

  /// Whether the element called [elementName] is on. `false` if there is no
  /// such element.
  bool isOn(String elementName) => this[elementName]?.isOn ?? false;

  @override
  Map<String, Object?> get _fields => {..._propertyFields, 'rule': rule};
}

/// A property made of status lights. Always read-only.
///
/// {@category Model}
final class LightProperty extends IndiProperty<LightElement> {
  /// Creates a light property.
  LightProperty({
    required super.device,
    required super.name,
    super.label,
    super.group,
    super.state,
    super.timestamp,
    required super.elements,
  }) : super(permission: PropertyPermission.readOnly);

  @override
  PropertyType get type => PropertyType.light;
}

/// A property made of BLOBs (binary data), such as camera images.
///
/// {@category Model}
final class BlobProperty extends IndiProperty<BlobElement> {
  /// Creates a BLOB property.
  BlobProperty({
    required super.device,
    required super.name,
    super.label,
    super.group,
    super.state,
    super.permission = PropertyPermission.readOnly,
    super.timeout,
    super.timestamp,
    required super.elements,
  });

  @override
  PropertyType get type => PropertyType.blob;
}
