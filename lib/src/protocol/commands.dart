import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../model/enums.dart';
import '../util/equality.dart';

/// The INDI protocol version implemented by this package.
const String indiProtocolVersion = '1.7';

/// Value semantics shared by every protocol class: equality and `toString`
/// derived from a map of fields.
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

/// A message of the INDI protocol: one top-level XML element.
///
/// Each subclass maps to one element of the INDI 1.7 DTD, plus the
/// `pingRequest`/`pingReply` extension of INDI 2.
///
/// {@category Protocol}
@immutable
sealed class IndiCommand with _Fields {
  const IndiCommand();
}

// ---------------------------------------------------------------------------
// Elements inside vectors.
// ---------------------------------------------------------------------------

/// An element inside a `def*Vector`: the definition of one value.
///
/// {@category Protocol}
@immutable
sealed class DefElement with _Fields {
  const DefElement({required this.name, this.label});

  /// The element name, unique within its property.
  final String name;

  /// A human readable label, or `null` to use [name].
  final String? label;
}

/// A `defText` element.
///
/// {@category Protocol}
final class DefText extends DefElement {
  /// Creates a text element definition.
  const DefText({required super.name, super.label, this.value = ''});

  /// The initial text.
  final String value;

  @override
  Map<String, Object?> get _fields =>
      {'name': name, 'label': label, 'value': value};
}

/// A `defNumber` element.
///
/// {@category Protocol}
final class DefNumber extends DefElement {
  /// Creates a number element definition.
  const DefNumber({
    required super.name,
    super.label,
    this.format = '%g',
    this.min = 0,
    this.max = 0,
    this.step = 0,
    this.value = 0,
  });

  /// The printf-style display format, possibly sexagesimal (`%m`).
  final String format;

  /// The minimum value. When [min] equals [max] the range is unbounded.
  final double min;

  /// The maximum value. When [min] equals [max] the range is unbounded.
  final double max;

  /// The step between allowed values, or 0 for any value.
  final double step;

  /// The initial value.
  final double value;

  @override
  Map<String, Object?> get _fields => {
        'name': name,
        'label': label,
        'format': format,
        'min': min,
        'max': max,
        'step': step,
        'value': value,
      };
}

/// A `defSwitch` element.
///
/// {@category Protocol}
final class DefSwitch extends DefElement {
  /// Creates a switch element definition.
  const DefSwitch({required super.name, super.label, required this.state});

  /// The initial state.
  final SwitchState state;

  @override
  Map<String, Object?> get _fields =>
      {'name': name, 'label': label, 'state': state};
}

/// A `defLight` element.
///
/// {@category Protocol}
final class DefLight extends DefElement {
  /// Creates a light element definition.
  const DefLight({required super.name, super.label, required this.state});

  /// The initial state.
  final PropertyState state;

  @override
  Map<String, Object?> get _fields =>
      {'name': name, 'label': label, 'state': state};
}

/// A `defBLOB` element. BLOB definitions carry no data.
///
/// {@category Protocol}
final class DefBlob extends DefElement {
  /// Creates a BLOB element definition.
  const DefBlob({required super.name, super.label});

  @override
  Map<String, Object?> get _fields => {'name': name, 'label': label};
}

/// An element carrying a value inside a `set*Vector` or `new*Vector`.
///
/// {@category Protocol}
@immutable
sealed class OneElement with _Fields {
  const OneElement({required this.name});

  /// The name of the element the value belongs to.
  final String name;
}

/// A `oneText` element.
///
/// {@category Protocol}
final class OneText extends OneElement {
  /// Creates a text value.
  const OneText({required super.name, required this.value});

  /// The text.
  final String value;

  @override
  Map<String, Object?> get _fields => {'name': name, 'value': value};
}

/// A `oneNumber` element.
///
/// {@category Protocol}
final class OneNumber extends OneElement {
  /// Creates a number value.
  const OneNumber({
    required super.name,
    required this.value,
    this.min,
    this.max,
    this.step,
  });

  /// The number.
  final double value;

  /// A new minimum, sent by drivers that change the range of an element
  /// (libindi `IUUpdateMinMax`); otherwise `null`.
  final double? min;

  /// A new maximum, or `null` if the range is unchanged.
  final double? max;

  /// A new step, or `null` if the step is unchanged.
  final double? step;

  @override
  Map<String, Object?> get _fields =>
      {'name': name, 'value': value, 'min': min, 'max': max, 'step': step};
}

/// A `oneSwitch` element.
///
/// {@category Protocol}
final class OneSwitch extends OneElement {
  /// Creates a switch value.
  const OneSwitch({required super.name, required this.state});

  /// The switch state.
  final SwitchState state;

  @override
  Map<String, Object?> get _fields => {'name': name, 'state': state};
}

/// A `oneLight` element.
///
/// {@category Protocol}
final class OneLight extends OneElement {
  /// Creates a light value.
  const OneLight({required super.name, required this.state});

  /// The light state.
  final PropertyState state;

  @override
  Map<String, Object?> get _fields => {'name': name, 'state': state};
}

/// A `oneBLOB` element.
///
/// {@category Protocol}
final class OneBlob extends OneElement {
  /// Creates a BLOB value holding [data].
  ///
  /// [size] defaults to the length of [data]; for compressed formats it is
  /// the uncompressed size.
  OneBlob({
    required super.name,
    required this.format,
    required this.data,
    int? size,
  }) : size = size ?? data.length;

  /// The format, as a file name extension such as `.fits`, `.jpg` or
  /// `.fits.z` (zlib-compressed FITS).
  final String format;

  /// The decoded bytes. Empty when the driver sent no data.
  final Uint8List data;

  /// The size in bytes of the data once decompressed.
  final int size;

  @override
  Map<String, Object?> get _fields =>
      {'name': name, 'format': format, 'size': size, 'data': data};
}

// ---------------------------------------------------------------------------
// Property definitions (server to client).
// ---------------------------------------------------------------------------

/// A `def*Vector` command: the server defines a property.
///
/// {@category Protocol}
sealed class DefVector<E extends DefElement> extends IndiCommand {
  const DefVector({
    required this.device,
    required this.name,
    this.label,
    this.group,
    this.state = PropertyState.idle,
    this.timeout,
    this.timestamp,
    this.message,
    required this.elements,
  });

  /// The device that owns the property.
  final String device;

  /// The property name, unique within the device.
  final String name;

  /// A human readable label, or `null` to use [name].
  final String? label;

  /// The group used to organize properties in user interfaces.
  final String? group;

  /// The initial state.
  final PropertyState state;

  /// The worst-case time, in seconds, the driver needs to apply a change.
  final double? timeout;

  /// When the driver generated the definition.
  final DateTime? timestamp;

  /// A message for the user that accompanies the definition.
  final String? message;

  /// The element definitions.
  final List<E> elements;

  /// The type of the property.
  PropertyType get type;

  Map<String, Object?> get _vectorFields => {
        'device': device,
        'name': name,
        'label': label,
        'group': group,
        'state': state,
        'timeout': timeout,
        'timestamp': timestamp,
        'message': message,
      };
}

/// A `defTextVector` command.
///
/// {@category Protocol}
final class DefTextVector extends DefVector<DefText> {
  /// Creates a text property definition.
  const DefTextVector({
    required super.device,
    required super.name,
    super.label,
    super.group,
    super.state,
    this.perm = PropertyPermission.readWrite,
    super.timeout,
    super.timestamp,
    super.message,
    required super.elements,
  });

  /// The permission hint.
  final PropertyPermission perm;

  @override
  PropertyType get type => PropertyType.text;

  @override
  Map<String, Object?> get _fields =>
      {..._vectorFields, 'perm': perm, 'elements': elements};
}

/// A `defNumberVector` command.
///
/// {@category Protocol}
final class DefNumberVector extends DefVector<DefNumber> {
  /// Creates a number property definition.
  const DefNumberVector({
    required super.device,
    required super.name,
    super.label,
    super.group,
    super.state,
    this.perm = PropertyPermission.readWrite,
    super.timeout,
    super.timestamp,
    super.message,
    required super.elements,
  });

  /// The permission hint.
  final PropertyPermission perm;

  @override
  PropertyType get type => PropertyType.number;

  @override
  Map<String, Object?> get _fields =>
      {..._vectorFields, 'perm': perm, 'elements': elements};
}

/// A `defSwitchVector` command.
///
/// {@category Protocol}
final class DefSwitchVector extends DefVector<DefSwitch> {
  /// Creates a switch property definition.
  const DefSwitchVector({
    required super.device,
    required super.name,
    super.label,
    super.group,
    super.state,
    this.perm = PropertyPermission.readWrite,
    this.rule = SwitchRule.anyOfMany,
    super.timeout,
    super.timestamp,
    super.message,
    required super.elements,
  });

  /// The permission hint.
  final PropertyPermission perm;

  /// The rule that constrains which switches can be on.
  final SwitchRule rule;

  @override
  PropertyType get type => PropertyType.switches;

  @override
  Map<String, Object?> get _fields =>
      {..._vectorFields, 'perm': perm, 'rule': rule, 'elements': elements};
}

/// A `defLightVector` command. Lights are always read-only.
///
/// {@category Protocol}
final class DefLightVector extends DefVector<DefLight> {
  /// Creates a light property definition.
  const DefLightVector({
    required super.device,
    required super.name,
    super.label,
    super.group,
    super.state,
    super.timestamp,
    super.message,
    required super.elements,
  });

  @override
  PropertyType get type => PropertyType.light;

  @override
  Map<String, Object?> get _fields => {..._vectorFields, 'elements': elements};
}

/// A `defBLOBVector` command.
///
/// {@category Protocol}
final class DefBlobVector extends DefVector<DefBlob> {
  /// Creates a BLOB property definition.
  const DefBlobVector({
    required super.device,
    required super.name,
    super.label,
    super.group,
    super.state,
    this.perm = PropertyPermission.readOnly,
    super.timeout,
    super.timestamp,
    super.message,
    required super.elements,
  });

  /// The permission hint.
  final PropertyPermission perm;

  @override
  PropertyType get type => PropertyType.blob;

  @override
  Map<String, Object?> get _fields =>
      {..._vectorFields, 'perm': perm, 'elements': elements};
}

// ---------------------------------------------------------------------------
// Property updates (server to client).
// ---------------------------------------------------------------------------

/// A `set*Vector` command: the server reports new values for a property.
///
/// Only the elements that changed may be present, and the optional
/// attributes keep their previous values when absent.
///
/// {@category Protocol}
sealed class SetVector<E extends OneElement> extends IndiCommand {
  const SetVector({
    required this.device,
    required this.name,
    this.state,
    this.timeout,
    this.timestamp,
    this.message,
    required this.elements,
  });

  /// The device that owns the property.
  final String device;

  /// The property name.
  final String name;

  /// The new state, or `null` if it did not change.
  final PropertyState? state;

  /// The new timeout in seconds, or `null` if it did not change.
  final double? timeout;

  /// When the driver generated the update.
  final DateTime? timestamp;

  /// A message for the user that accompanies the update.
  final String? message;

  /// The new element values.
  final List<E> elements;

  /// The type of the property.
  PropertyType get type;

  @override
  Map<String, Object?> get _fields => {
        'device': device,
        'name': name,
        'state': state,
        'timeout': timeout,
        'timestamp': timestamp,
        'message': message,
        'elements': elements,
      };
}

/// A `setTextVector` command.
///
/// {@category Protocol}
final class SetTextVector extends SetVector<OneText> {
  /// Creates a text property update.
  const SetTextVector({
    required super.device,
    required super.name,
    super.state,
    super.timeout,
    super.timestamp,
    super.message,
    required super.elements,
  });

  @override
  PropertyType get type => PropertyType.text;
}

/// A `setNumberVector` command.
///
/// {@category Protocol}
final class SetNumberVector extends SetVector<OneNumber> {
  /// Creates a number property update.
  const SetNumberVector({
    required super.device,
    required super.name,
    super.state,
    super.timeout,
    super.timestamp,
    super.message,
    required super.elements,
  });

  @override
  PropertyType get type => PropertyType.number;
}

/// A `setSwitchVector` command.
///
/// {@category Protocol}
final class SetSwitchVector extends SetVector<OneSwitch> {
  /// Creates a switch property update.
  const SetSwitchVector({
    required super.device,
    required super.name,
    super.state,
    super.timeout,
    super.timestamp,
    super.message,
    required super.elements,
  });

  @override
  PropertyType get type => PropertyType.switches;
}

/// A `setLightVector` command.
///
/// {@category Protocol}
final class SetLightVector extends SetVector<OneLight> {
  /// Creates a light property update.
  const SetLightVector({
    required super.device,
    required super.name,
    super.state,
    super.timestamp,
    super.message,
    required super.elements,
  });

  @override
  PropertyType get type => PropertyType.light;
}

/// A `setBLOBVector` command.
///
/// {@category Protocol}
final class SetBlobVector extends SetVector<OneBlob> {
  /// Creates a BLOB property update.
  const SetBlobVector({
    required super.device,
    required super.name,
    super.state,
    super.timeout,
    super.timestamp,
    super.message,
    required super.elements,
  });

  @override
  PropertyType get type => PropertyType.blob;
}

// ---------------------------------------------------------------------------
// New values (client to server).
// ---------------------------------------------------------------------------

/// A `new*Vector` command: the client asks a driver to change a property.
///
/// {@category Protocol}
sealed class NewVector<E extends OneElement> extends IndiCommand {
  const NewVector({
    required this.device,
    required this.name,
    this.timestamp,
    required this.elements,
  });

  /// The device that owns the property.
  final String device;

  /// The property name.
  final String name;

  /// When the client generated the request. Optional.
  final DateTime? timestamp;

  /// The requested element values.
  final List<E> elements;

  /// The type of the property.
  PropertyType get type;

  @override
  Map<String, Object?> get _fields => {
        'device': device,
        'name': name,
        'timestamp': timestamp,
        'elements': elements,
      };
}

/// A `newTextVector` command.
///
/// {@category Protocol}
final class NewTextVector extends NewVector<OneText> {
  /// Creates a request to change a text property.
  const NewTextVector({
    required super.device,
    required super.name,
    super.timestamp,
    required super.elements,
  });

  @override
  PropertyType get type => PropertyType.text;
}

/// A `newNumberVector` command.
///
/// {@category Protocol}
final class NewNumberVector extends NewVector<OneNumber> {
  /// Creates a request to change a number property.
  const NewNumberVector({
    required super.device,
    required super.name,
    super.timestamp,
    required super.elements,
  });

  @override
  PropertyType get type => PropertyType.number;
}

/// A `newSwitchVector` command.
///
/// {@category Protocol}
final class NewSwitchVector extends NewVector<OneSwitch> {
  /// Creates a request to change a switch property.
  const NewSwitchVector({
    required super.device,
    required super.name,
    super.timestamp,
    required super.elements,
  });

  @override
  PropertyType get type => PropertyType.switches;
}

/// A `newBLOBVector` command.
///
/// {@category Protocol}
final class NewBlobVector extends NewVector<OneBlob> {
  /// Creates a request to upload BLOB data to a driver.
  const NewBlobVector({
    required super.device,
    required super.name,
    super.timestamp,
    required super.elements,
  });

  @override
  PropertyType get type => PropertyType.blob;
}

// ---------------------------------------------------------------------------
// Other commands.
// ---------------------------------------------------------------------------

/// A `getProperties` command: asks for property definitions.
///
/// Without [device] it asks for every device; without [name] for every
/// property of [device].
///
/// {@category Protocol}
final class GetProperties extends IndiCommand {
  /// Creates a request for property definitions.
  const GetProperties({
    this.version = indiProtocolVersion,
    this.device,
    this.name,
  });

  /// The protocol version spoken by the sender.
  final String version;

  /// The device to describe, or `null` for all devices.
  final String? device;

  /// The property to describe, or `null` for all properties.
  final String? name;

  @override
  Map<String, Object?> get _fields =>
      {'version': version, 'device': device, 'name': name};
}

/// An `enableBLOB` command: sets which BLOBs the server sends on this
/// connection.
///
/// Note that indiserver applies an `enableBLOB` without [name] to the whole
/// connection, not only to [device].
///
/// {@category Protocol}
final class EnableBlob extends IndiCommand {
  /// Creates a BLOB policy command.
  const EnableBlob({required this.mode, required this.device, this.name});

  /// The BLOB policy.
  final BlobMode mode;

  /// The device the policy applies to.
  final String device;

  /// The BLOB property the policy applies to, or `null` for all.
  final String? name;

  @override
  Map<String, Object?> get _fields =>
      {'mode': mode, 'device': device, 'name': name};
}

/// A `delProperty` command: a property, or a whole device, is gone.
///
/// {@category Protocol}
final class DelProperty extends IndiCommand {
  /// Creates a deletion command.
  const DelProperty({
    required this.device,
    this.name,
    this.timestamp,
    this.message,
  });

  /// The device.
  final String device;

  /// The deleted property, or `null` when the whole device is gone.
  final String? name;

  /// When the driver generated the deletion.
  final DateTime? timestamp;

  /// A message for the user.
  final String? message;

  @override
  Map<String, Object?> get _fields => {
        'device': device,
        'name': name,
        'timestamp': timestamp,
        'message': message,
      };
}

/// A `message` command: a log message from a driver or the server.
///
/// {@category Protocol}
final class MessageCommand extends IndiCommand {
  /// Creates a message.
  const MessageCommand({this.device, this.timestamp, required this.message});

  /// The device the message is about, or `null` for a generic message.
  final String? device;

  /// When the message was generated.
  final DateTime? timestamp;

  /// The text of the message.
  final String message;

  @override
  Map<String, Object?> get _fields =>
      {'device': device, 'timestamp': timestamp, 'message': message};
}

/// A `pingRequest` command (INDI 2 extension).
///
/// indiserver answers a client's request with a [PingReply] carrying the
/// same [uid], so it works as a keep-alive.
///
/// {@category Protocol}
final class PingRequest extends IndiCommand {
  /// Creates a ping request.
  const PingRequest({required this.uid});

  /// An identifier echoed in the reply.
  final String uid;

  @override
  Map<String, Object?> get _fields => {'uid': uid};
}

/// A `pingReply` command (INDI 2 extension).
///
/// {@category Protocol}
final class PingReply extends IndiCommand {
  /// Creates a ping reply.
  const PingReply({required this.uid});

  /// The identifier of the request being answered.
  final String uid;

  @override
  Map<String, Object?> get _fields => {'uid': uid};
}

/// A top-level element this package does not know.
///
/// Reported instead of failing so that newer servers keep working.
///
/// {@category Protocol}
final class UnknownCommand extends IndiCommand {
  /// Creates an unknown command.
  const UnknownCommand({required this.tag, this.attributes = const {}});

  /// The element name.
  final String tag;

  /// The element attributes.
  final Map<String, String> attributes;

  @override
  Map<String, Object?> get _fields => {'tag': tag, 'attributes': attributes};
}
