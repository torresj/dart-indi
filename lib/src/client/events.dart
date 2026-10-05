import 'package:meta/meta.dart';

import '../exceptions.dart';
import '../model/message.dart';
import '../model/properties.dart';
import 'connection_state.dart';
import 'indi_client.dart';

/// Something that happened on an `IndiClient`, delivered on
/// `IndiClient.events`.
///
/// The hierarchy is sealed, so a `switch` over it can be exhaustive.
/// The events mirror the callbacks of libindi's `BaseClient`
/// (`newDevice`, `newProperty`, `updateProperty`, …).
///
/// {@category Client}
@immutable
sealed class IndiEvent {
  const IndiEvent();
}

/// The connection state changed.
///
/// {@category Client}
final class ConnectionStateChanged extends IndiEvent {
  /// Creates the event.
  const ConnectionStateChanged(this.state);

  /// The new state.
  final IndiConnectionState state;

  @override
  String toString() => 'ConnectionStateChanged($state)';
}

/// A device appeared: the server defined its first property.
///
/// {@category Client}
final class DeviceAdded extends IndiEvent {
  /// Creates the event.
  const DeviceAdded(this.device);

  /// The new device.
  final IndiDevice device;

  @override
  String toString() => 'DeviceAdded(${device.name})';
}

/// A device disappeared, because the driver deleted it or it was not
/// defined again after a reconnect.
///
/// {@category Client}
final class DeviceRemoved extends IndiEvent {
  /// Creates the event.
  const DeviceRemoved(this.device);

  /// The removed device. It is no longer available.
  final IndiDevice device;

  @override
  String toString() => 'DeviceRemoved(${device.name})';
}

/// An event about one property of a device.
///
/// {@category Client}
sealed class PropertyEvent extends IndiEvent {
  const PropertyEvent(this.device, this.property);

  /// The device that owns the property.
  final IndiDevice device;

  /// The property, as it is after the event.
  final IndiProperty property;
}

/// The server defined a new property.
///
/// {@category Client}
final class PropertyDefined extends PropertyEvent {
  /// Creates the event.
  const PropertyDefined(super.device, super.property);

  @override
  String toString() => 'PropertyDefined(${device.name}.${property.name})';
}

/// A property changed: new values, a new state, or a new definition.
///
/// {@category Client}
final class PropertyUpdated extends PropertyEvent {
  /// Creates the event.
  const PropertyUpdated(super.device, super.property, this.previous);

  /// The property as it was before the update.
  final IndiProperty previous;

  @override
  String toString() =>
      'PropertyUpdated(${device.name}.${property.name}, ${property.state})';
}

/// The server deleted a property.
///
/// {@category Client}
final class PropertyRemoved extends PropertyEvent {
  /// Creates the event.
  const PropertyRemoved(super.device, super.property);

  @override
  String toString() => 'PropertyRemoved(${device.name}.${property.name})';
}

/// A message arrived from a driver or from the server.
///
/// {@category Client}
final class MessageReceived extends IndiEvent {
  /// Creates the event.
  const MessageReceived(this.message, this.device);

  /// The message.
  final IndiMessage message;

  /// The device the message is about, or `null` for a generic message.
  final IndiDevice? device;

  @override
  String toString() => 'MessageReceived(${message.text})';
}

/// The connection was restored and the session was resumed: properties
/// were requested again, and anything not defined again was removed.
///
/// {@category Client}
final class SessionResumed extends IndiEvent {
  /// Creates the event.
  const SessionResumed({
    required this.downtime,
    required this.attempts,
    required this.devices,
  });

  /// How long the connection was down.
  final Duration downtime;

  /// How many connection attempts it took.
  final int attempts;

  /// The devices available after resuming.
  final List<IndiDevice> devices;

  @override
  String toString() =>
      'SessionResumed(downtime: $downtime, attempts: $attempts, '
      'devices: ${devices.map((d) => d.name).join(', ')})';
}

/// Received data could not be understood. The connection stays open.
///
/// {@category Client}
final class ProtocolErrorReceived extends IndiEvent {
  /// Creates the event.
  const ProtocolErrorReceived(this.error);

  /// The problem.
  final IndiProtocolException error;

  @override
  String toString() => 'ProtocolErrorReceived(${error.message})';
}
