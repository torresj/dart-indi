import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:logging/logging.dart';

import '../exceptions.dart';
import '../protocol/commands.dart';
import '../protocol/decoder.dart';
import '../protocol/encoder.dart';
import '../transport/transport.dart';
import 'client_options.dart';
import 'connection_state.dart';

/// Owns one connection to the server: opens it, decodes what arrives,
/// sends keep-alive pings, and reconnects with backoff when it is lost.
///
/// Internal to the client.
final class ConnectionSupervisor {
  /// Creates a supervisor. Nothing happens until [start].
  ConnectionSupervisor({
    required this.transport,
    required this.connectTimeout,
    required this.reconnect,
    required this.heartbeat,
    required this.retryInitialConnect,
    required this.onCommand,
    required this.onProtocolError,
    required this.onConnected,
    required this.onConnectionLost,
    required this.onStateChanged,
    required this.logger,
    math.Random? random,
  }) : _random = random ?? math.Random();

  /// The transport used for every connection attempt.
  final IndiTransport transport;

  /// The time limit for each connection attempt.
  final Duration connectTimeout;

  /// How to reconnect after a loss.
  final ReconnectPolicy reconnect;

  /// Keep-alive configuration.
  final HeartbeatOptions heartbeat;

  /// Whether the first connection is retried when it fails.
  final bool retryInitialConnect;

  /// Called with every command received.
  final void Function(IndiCommand command) onCommand;

  /// Called when received data can't be decoded.
  final void Function(IndiProtocolException error) onProtocolError;

  /// Called when a connection is established. `isReconnect` is `true` when
  /// it replaces a lost one; `attempts` is how many tries it took.
  final void Function({required bool isReconnect, required int attempts})
      onConnected;

  /// Called when an established connection is lost.
  final void Function(Object error) onConnectionLost;

  /// Called on every state change.
  final void Function(IndiConnectionState state) onStateChanged;

  /// Where diagnostics are logged.
  final Logger logger;

  final math.Random _random;

  IndiConnectionState _state = const IndiDisconnected();
  IndiConnection? _connection;
  // Cancelled in _detach.
  // ignore: cancel_subscriptions
  StreamSubscription<Uint8List>? _subscription;
  Timer? _retryTimer;
  Timer? _heartbeatTimer;
  Completer<void>? _startCompleter;

  /// Incremented whenever the current connection or attempt is abandoned,
  /// so callbacks from stale connections are ignored.
  int _generation = 0;
  bool _wanted = false;
  bool _closed = false;
  bool _isReconnect = false;
  int _attempt = 0;

  DateTime _lastReceived = clock.now();
  int _pingCounter = 0;
  int _unansweredPings = 0;
  bool? _pingSupported;

  /// The current state.
  IndiConnectionState get state => _state;

  /// Whether the server answers keep-alive pings: `null` while unknown.
  bool? get pingSupported => _pingSupported;

  /// Connects, and keeps the connection alive until [stop] or [close].
  ///
  /// Completes when connected. Throws an [IndiConnectionException] if the
  /// connection can't be established (after retrying, if
  /// [retryInitialConnect] is set).
  Future<void> start() {
    if (_closed) {
      return Future.error(const IndiClosedException('The client is closed'));
    }
    if (_wanted) {
      return _startCompleter?.future ?? Future<void>.value();
    }
    _wanted = true;
    _isReconnect = false;
    _attempt = 0;
    final completer = _startCompleter = Completer<void>();
    unawaited(_connect());
    return completer.future;
  }

  /// Disconnects and stops reconnecting. [start] can be called again.
  Future<void> stop() async {
    if (_closed) return;
    _wanted = false;
    _generation++;
    _retryTimer?.cancel();
    _failStart(const IndiConnectionException('Disconnected by the client'));
    await _detach();
    _setState(const IndiDisconnected());
  }

  /// Disconnects for good.
  Future<void> close() async {
    if (_closed) return;
    await stop();
    _closed = true;
    _setState(const IndiClosed());
  }

  /// Sends [command] on the current connection.
  ///
  /// Throws an [IndiNotConnectedException] when not connected.
  void send(IndiCommand command) {
    final connection = _connection;
    if (connection == null || _state is! IndiConnected) {
      throw IndiNotConnectedException(
        'Cannot send ${command.runtimeType}: not connected to '
        '${transport.description}',
      );
    }
    if (logger.isLoggable(Level.FINEST)) logger.finest('> $command');
    for (final chunk in encodeIndiCommandChunks(command)) {
      connection.add(chunk);
    }
  }

  Future<void> _connect() async {
    _attempt++;
    final generation = ++_generation;
    _setState(IndiConnecting(attempt: _attempt));
    final IndiConnection connection;
    try {
      connection = await transport.connect(timeout: connectTimeout);
    } on Object catch (error) {
      if (generation != _generation || !_wanted) return;
      logger.info('Connection to ${transport.description} failed: $error');
      _scheduleRetry(error);
      return;
    }
    if (generation != _generation || !_wanted) {
      unawaited(connection.close());
      return;
    }
    _attach(connection, generation);
    final attempts = _attempt;
    _attempt = 0;
    logger.info('Connected to ${transport.description}');
    _setState(const IndiConnected());
    onConnected(isReconnect: _isReconnect, attempts: attempts);
    final completer = _startCompleter;
    _startCompleter = null;
    completer?.complete();
  }

  void _scheduleRetry(Object error) {
    final next = _attempt + 1;
    // The very first attempt is not a retry.
    final retry = _isReconnect ? next : next - 1;
    final allowed =
        (_isReconnect || retryInitialConnect) && reconnect.allows(retry);
    if (!allowed) {
      _wanted = false;
      _failStart(error is IndiException
          ? error
          : IndiConnectionException(
              'Cannot connect to ${transport.description}',
              cause: error,
            ));
      _setState(IndiDisconnected(error: error));
      return;
    }
    final delay = reconnect.delayFor(retry, _random);
    _setState(IndiReconnecting(attempt: next, delay: delay, error: error));
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      if (_wanted) unawaited(_connect());
    });
  }

  void _attach(IndiConnection connection, int generation) {
    _connection = connection;
    _lastReceived = clock.now();
    _pingSupported = null;
    _unansweredPings = 0;
    final decoder = IndiStreamDecoder(
      onCommand: (command) {
        if (generation != _generation) return;
        if (command is PingReply) {
          _pingSupported = true;
          _unansweredPings = 0;
        }
        if (logger.isLoggable(Level.FINEST)) logger.finest('< $command');
        onCommand(command);
      },
      onError: (error) {
        if (generation != _generation) return;
        logger.warning(error.message);
        onProtocolError(error);
      },
    );
    _subscription = connection.input.listen(
      (bytes) {
        if (generation != _generation) return;
        _lastReceived = clock.now();
        decoder.add(bytes);
      },
      onError: (Object error) => _handleLoss(generation, error),
      onDone: () => _handleLoss(
        generation,
        const IndiConnectionLostException('The server closed the connection'),
      ),
      cancelOnError: true,
    );
    if (heartbeat.enabled && heartbeat.interval > Duration.zero) {
      _heartbeatTimer = Timer.periodic(
        heartbeat.interval,
        (_) => _heartbeatTick(generation),
      );
    }
  }

  void _heartbeatTick(int generation) {
    if (generation != _generation || _state is! IndiConnected) return;
    final silence = clock.now().difference(_lastReceived);
    if (_pingSupported == true && silence > heartbeat.timeout) {
      logger.warning('Nothing received for $silence; reconnecting');
      _handleLoss(
        generation,
        IndiConnectionLostException(
          'Nothing received from the server for ${silence.inSeconds}s',
        ),
      );
      return;
    }
    if (_pingSupported == false) return;
    if (_pingSupported == null && _unansweredPings >= 2) {
      _pingSupported = false;
      logger.info('The server does not answer pings; keep-alive disabled');
      return;
    }
    _unansweredPings++;
    try {
      send(PingRequest(uid: 'ping${++_pingCounter}'));
    } on IndiException {
      // The connection is going away; the loss handler takes over.
    }
  }

  void _handleLoss(int generation, Object error) {
    if (generation != _generation) return;
    _generation++;
    unawaited(_detach());
    if (!_wanted) {
      _setState(IndiDisconnected(error: error));
      return;
    }
    logger.warning('Connection to ${transport.description} lost: $error');
    onConnectionLost(error);
    _isReconnect = true;
    _attempt = 0;
    _scheduleRetry(error);
  }

  Future<void> _detach() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    final subscription = _subscription;
    final connection = _connection;
    _subscription = null;
    _connection = null;
    await subscription?.cancel();
    await connection?.close();
  }

  void _failStart(Object error) {
    final completer = _startCompleter;
    _startCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(error);
    }
  }

  void _setState(IndiConnectionState state) {
    if (state == _state) return;
    _state = state;
    onStateChanged(state);
  }
}
