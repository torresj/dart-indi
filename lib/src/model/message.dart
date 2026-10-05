import 'package:meta/meta.dart';

/// The severity of an [IndiMessage], taken from the `[LEVEL]` prefix that
/// libindi drivers put on their messages.
///
/// {@category Model}
enum IndiMessageLevel {
  /// A debug message (`[DEBUG]`).
  debug,

  /// An informational message (`[INFO]`), and messages without a prefix.
  info,

  /// A warning (`[WARNING]`).
  warning,

  /// An error (`[ERROR]`).
  error,
}

final RegExp _levelPrefix = RegExp(
  r'^\s*\[(DEBUG|INFO|WARNING|ERROR|SCOPE)\]\s*',
  caseSensitive: false,
);

/// A log message from a driver or from the server.
///
/// Messages arrive as `message` commands and as the `message` attribute of
/// property definitions, updates and deletions.
///
/// {@category Model}
@immutable
final class IndiMessage {
  /// Creates a message.
  IndiMessage({this.device, required this.text, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now().toUtc();

  /// The device the message is about, or `null` for a generic message.
  final String? device;

  /// The full text, as sent by the driver.
  final String text;

  /// When the message was generated (UTC). The arrival time when the
  /// driver sent no timestamp.
  final DateTime timestamp;

  /// The severity, parsed from a `[LEVEL]` prefix in [text].
  IndiMessageLevel get level {
    final match = _levelPrefix.firstMatch(text);
    return switch (match?.group(1)?.toUpperCase()) {
      'DEBUG' || 'SCOPE' => IndiMessageLevel.debug,
      'WARNING' => IndiMessageLevel.warning,
      'ERROR' => IndiMessageLevel.error,
      _ => IndiMessageLevel.info,
    };
  }

  /// [text] without the `[LEVEL]` prefix.
  String get body => text.replaceFirst(_levelPrefix, '');

  @override
  bool operator ==(Object other) =>
      other is IndiMessage &&
      other.device == device &&
      other.text == text &&
      other.timestamp == timestamp;

  @override
  int get hashCode => Object.hash(device, text, timestamp);

  @override
  String toString() => device == null
      ? 'IndiMessage($timestamp: $text)'
      : 'IndiMessage($device, $timestamp: $text)';
}
