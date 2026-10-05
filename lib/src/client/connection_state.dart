import 'package:meta/meta.dart';

/// The state of the connection between an `IndiClient` and its server.
///
/// The hierarchy is sealed, so UIs can `switch` over it exhaustively:
///
/// ```dart
/// final label = switch (client.connectionState) {
///   IndiConnected() => 'Online',
///   IndiConnecting(:final attempt) => 'Connecting (attempt $attempt)…',
///   IndiReconnecting(:final delay) => 'Retrying in ${delay.inSeconds}s',
///   IndiDisconnected() => 'Offline',
///   IndiClosed() => 'Closed',
/// };
/// ```
///
/// {@category Client}
@immutable
sealed class IndiConnectionState {
  const IndiConnectionState();

  /// Whether commands can be sent.
  bool get isConnected => this is IndiConnected;
}

/// Not connected, and not trying to connect. The initial state, and the
/// state after `IndiClient.disconnect` or after reconnecting gave up.
///
/// {@category Client}
final class IndiDisconnected extends IndiConnectionState {
  /// Creates a disconnected state, optionally caused by [error].
  const IndiDisconnected({this.error});

  /// The error that ended the last connection, if any.
  final Object? error;

  @override
  bool operator ==(Object other) =>
      other is IndiDisconnected && other.error == error;

  @override
  int get hashCode => Object.hash(IndiDisconnected, error);

  @override
  String toString() =>
      error == null ? 'IndiDisconnected()' : 'IndiDisconnected($error)';
}

/// Opening a connection to the server.
///
/// {@category Client}
final class IndiConnecting extends IndiConnectionState {
  /// Creates a connecting state for connection attempt [attempt].
  const IndiConnecting({this.attempt = 1});

  /// The attempt number: 1 for the first try, higher while reconnecting.
  final int attempt;

  @override
  bool operator ==(Object other) =>
      other is IndiConnecting && other.attempt == attempt;

  @override
  int get hashCode => Object.hash(IndiConnecting, attempt);

  @override
  String toString() => 'IndiConnecting(attempt: $attempt)';
}

/// Connected to the server.
///
/// {@category Client}
final class IndiConnected extends IndiConnectionState {
  /// Creates a connected state.
  const IndiConnected();

  @override
  bool operator ==(Object other) => other is IndiConnected;

  @override
  int get hashCode => (IndiConnected).hashCode;

  @override
  String toString() => 'IndiConnected()';
}

/// The connection was lost; waiting [delay] before reconnection attempt
/// [attempt].
///
/// {@category Client}
final class IndiReconnecting extends IndiConnectionState {
  /// Creates a reconnecting state.
  const IndiReconnecting({
    required this.attempt,
    required this.delay,
    this.error,
  });

  /// The number of the next connection attempt.
  final int attempt;

  /// How long until the next attempt.
  final Duration delay;

  /// The error that caused the loss or made the last attempt fail.
  final Object? error;

  @override
  bool operator ==(Object other) =>
      other is IndiReconnecting &&
      other.attempt == attempt &&
      other.delay == delay &&
      other.error == error;

  @override
  int get hashCode => Object.hash(IndiReconnecting, attempt, delay, error);

  @override
  String toString() => 'IndiReconnecting(attempt: $attempt, delay: $delay'
      '${error == null ? '' : ', error: $error'})';
}

/// The client was closed and can't be used anymore.
///
/// {@category Client}
final class IndiClosed extends IndiConnectionState {
  /// Creates a closed state.
  const IndiClosed();

  @override
  bool operator ==(Object other) => other is IndiClosed;

  @override
  int get hashCode => (IndiClosed).hashCode;

  @override
  String toString() => 'IndiClosed()';
}
