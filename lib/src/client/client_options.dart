import 'dart:math' as math;

import 'package:meta/meta.dart';

/// Configuration for an `IndiClient`.
///
/// {@category Client}
@immutable
final class IndiClientOptions {
  /// Creates client options. The defaults suit most applications.
  const IndiClientOptions({
    this.connectTimeout = const Duration(seconds: 10),
    this.reconnect = const ReconnectPolicy(),
    this.retryInitialConnect = false,
    this.heartbeat = const HeartbeatOptions(),
    this.watchDevices = const {},
    this.commandTimeout,
    this.validateValues = true,
    this.resumeSettleTime = const Duration(seconds: 2),
    this.resumeMaxSettleTime = const Duration(seconds: 10),
    this.messageHistory = 100,
    this.separateBlobConnection = false,
  });

  /// The time limit for opening a connection.
  final Duration connectTimeout;

  /// How to reconnect after the connection is lost.
  final ReconnectPolicy reconnect;

  /// Whether `IndiClient.connect` keeps retrying, following [reconnect],
  /// when the first attempt fails. When `false` (the default), the first
  /// failure is thrown so the user can fix the server address.
  final bool retryInitialConnect;

  /// Keep-alive pings used to detect dead connections.
  final HeartbeatOptions heartbeat;

  /// The devices to track. Empty (the default) tracks every device on the
  /// server. When set, only these devices are requested and everything else
  /// is ignored, which saves bandwidth on busy servers.
  final Set<String> watchDevices;

  /// The default time limit for commands sent with `IndiDevice.sendNumbers`
  /// and friends, or `null` (the default) to wait as long as needed.
  ///
  /// Pending commands always fail when the connection is lost or the
  /// property is deleted, so they never hang forever on a broken link.
  final Duration? commandTimeout;

  /// Whether commands are checked locally before sending: element names,
  /// write permission, switch rules and number ranges.
  final bool validateValues;

  /// After a reconnect, properties are re-requested. The session is
  /// considered fully restored once no new definition has arrived for this
  /// long; properties and devices that were not defined again are then
  /// removed. See `SessionResumed`.
  final Duration resumeSettleTime;

  /// The longest time to wait for definitions after a reconnect, even if
  /// they keep arriving.
  final Duration resumeMaxSettleTime;

  /// How many recent messages the client and each device keep.
  final int messageHistory;

  /// Whether BLOBs (such as images) are received on a second connection
  /// in `Only` mode, so that large downloads never delay control traffic.
  /// Recommended for camera applications.
  final bool separateBlobConnection;
}

/// When and how often to reconnect after a lost connection.
///
/// Delays grow exponentially from [initialDelay] by [multiplier] up to
/// [maxDelay], with a random [jitter] so that many clients don't reconnect
/// at the same instant.
///
/// {@category Client}
@immutable
final class ReconnectPolicy {
  /// Creates a policy that reconnects with exponential backoff.
  const ReconnectPolicy({
    this.initialDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.multiplier = 2,
    this.jitter = 0.2,
    this.maxAttempts,
  }) : enabled = true;

  /// A policy that never reconnects.
  const ReconnectPolicy.disabled()
      : enabled = false,
        initialDelay = Duration.zero,
        maxDelay = Duration.zero,
        multiplier = 1,
        jitter = 0,
        maxAttempts = 0;

  /// Whether to reconnect at all.
  final bool enabled;

  /// The delay before the first reconnection attempt.
  final Duration initialDelay;

  /// The longest delay between attempts.
  final Duration maxDelay;

  /// The factor applied to the delay after each failed attempt.
  final double multiplier;

  /// The random variation applied to each delay, as a fraction: 0.2 means
  /// ±20%.
  final double jitter;

  /// The maximum number of consecutive attempts, or `null` to retry
  /// forever.
  final int? maxAttempts;

  /// Whether reconnection attempt number [attempt] (starting at 1) is
  /// allowed.
  bool allows(int attempt) =>
      enabled && (maxAttempts == null || attempt <= maxAttempts!);

  /// The delay before reconnection attempt number [attempt] (starting at 1).
  Duration delayFor(int attempt, [math.Random? random]) {
    final base = initialDelay.inMicroseconds *
        math.pow(multiplier, math.max(0, attempt - 1));
    final capped = math.min(base, maxDelay.inMicroseconds.toDouble());
    final variation =
        jitter == 0 ? 0.0 : ((random ?? math.Random()).nextDouble() * 2 - 1);
    final micros = capped * (1 + jitter * variation);
    return Duration(microseconds: math.max(0, micros.round()));
  }
}

/// Keep-alive pings that detect connections that died silently, for
/// example when a Wi-Fi network drops without closing the socket.
///
/// The client sends a `pingRequest` every [interval]; indiserver 2.x answers
/// with a `pingReply`. If nothing at all is received for [timeout], the
/// connection is considered dead and is reconnected. Servers that don't
/// answer pings (indiserver before 2.0) are detected automatically, and
/// pings are then turned off.
///
/// {@category Client}
@immutable
final class HeartbeatOptions {
  /// Creates heartbeat options. [timeout] defaults to three intervals.
  const HeartbeatOptions({
    this.interval = const Duration(seconds: 10),
    Duration? timeout,
  })  : enabled = true,
        _timeout = timeout;

  /// Disables keep-alive pings. Dead connections are then only detected
  /// when the operating system reports them.
  const HeartbeatOptions.disabled()
      : enabled = false,
        interval = Duration.zero,
        _timeout = null;

  /// Whether pings are sent.
  final bool enabled;

  /// The time between pings.
  final Duration interval;

  final Duration? _timeout;

  /// How long without receiving anything before the connection is
  /// considered dead.
  Duration get timeout => _timeout ?? interval * 3;
}

/// When a command sent with `IndiDevice.sendNumbers` and friends is
/// considered complete.
///
/// {@category Client}
enum CommandCompletion {
  /// As soon as the command is written to the connection.
  sent,

  /// On the first update of the property that is not `Busy`. This is the
  /// usual INDI convention and suits most properties.
  nextUpdate,

  /// Only after the property went `Busy` and then left that state, or when
  /// an update reports exactly the requested values. Use it for properties
  /// that the driver also updates on its own, such as mount coordinates
  /// while tracking, so that a periodic update that was already on its way
  /// is not mistaken for the answer.
  afterBusy,
}
