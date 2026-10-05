/// The base class of every exception thrown by this package.
///
/// The hierarchy is sealed, so a `switch` over an [IndiException] can be
/// exhaustive.
///
/// {@category Client}
sealed class IndiException implements Exception {
  const IndiException(this.message);

  /// A human readable description of the problem.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Received data that does not follow the INDI protocol.
///
/// The client reports these as events and keeps the connection open, so a
/// single malformed message never brings down a session.
///
/// {@category Client}
final class IndiProtocolException extends IndiException {
  /// Creates a protocol exception.
  const IndiProtocolException(super.message);
}

/// Connecting to an INDI server failed.
///
/// {@category Client}
final class IndiConnectionException extends IndiException {
  /// Creates a connection exception, optionally wrapping the underlying
  /// [cause].
  const IndiConnectionException(super.message, {this.cause});

  /// The error raised by the transport, if any.
  final Object? cause;

  @override
  String toString() =>
      cause == null ? super.toString() : '${super.toString()} ($cause)';
}

/// The connection to the server was lost while an operation was pending.
///
/// Pending commands are never replayed after a reconnect, because a command
/// executed late (a slew, for example) could be dangerous for the hardware.
///
/// {@category Client}
final class IndiConnectionLostException extends IndiException {
  /// Creates a connection lost exception.
  const IndiConnectionLostException(super.message);
}

/// An operation needs a connection, but the client is not connected.
///
/// {@category Client}
final class IndiNotConnectedException extends IndiException {
  /// Creates a not connected exception.
  const IndiNotConnectedException(super.message);
}

/// The client was closed, so the operation can't complete.
///
/// {@category Client}
final class IndiClosedException extends IndiException {
  /// Creates a closed exception.
  const IndiClosedException(super.message);
}

/// An operation did not complete within its time limit.
///
/// {@category Client}
final class IndiTimeoutException extends IndiException {
  /// Creates a timeout exception for an operation limited to [timeout].
  const IndiTimeoutException(super.message, this.timeout);

  /// The time limit that was exceeded.
  final Duration timeout;
}

/// A property went to the `Alert` state in response to a command.
///
/// {@category Client}
final class IndiPropertyAlertException extends IndiException {
  /// Creates an alert exception for [property] of [device].
  const IndiPropertyAlertException(
    super.message, {
    required this.device,
    required this.property,
  });

  /// The name of the device that owns the property.
  final String device;

  /// The name of the property that went to `Alert`.
  final String property;
}

/// A command targeted a property the client is not allowed to write.
///
/// {@category Client}
final class IndiPermissionException extends IndiException {
  /// Creates a permission exception.
  const IndiPermissionException(super.message);
}

/// A command contained values the property can't accept, such as an
/// unknown element name or a number outside the allowed range.
///
/// {@category Client}
final class IndiValidationException extends IndiException {
  /// Creates a validation exception.
  const IndiValidationException(super.message);
}

/// A device, property or element does not exist.
///
/// {@category Client}
final class IndiNotFoundException extends IndiException {
  /// Creates a not found exception.
  const IndiNotFoundException(super.message);
}

/// A property was deleted by the driver while a command on it was pending.
///
/// {@category Client}
final class IndiPropertyRemovedException extends IndiException {
  /// Creates a property removed exception.
  const IndiPropertyRemovedException(super.message);
}
