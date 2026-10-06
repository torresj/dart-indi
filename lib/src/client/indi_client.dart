import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';

import '../exceptions.dart';
import '../model/blob.dart';
import '../model/device_interface.dart';
import '../model/enums.dart';
import '../model/message.dart';
import '../model/properties.dart';
import '../model/property_updates.dart';
import '../protocol/commands.dart';
import '../transport/default_transport.dart';
import '../transport/transport.dart';
import 'client_options.dart';
import 'command_tracker.dart';
import 'connection_state.dart';
import 'connection_supervisor.dart';
import 'events.dart';

part 'device.dart';

final Logger _log = Logger('indi.client');

/// A client for an INDI server: the entry point of this package.
///
/// ```dart
/// final client = IndiClient(host: 'astroberry.local');
/// await client.connect();
/// final mount = await client.waitForDevice('Telescope Simulator');
/// await mount.connect();
/// ```
///
/// The client keeps a live model of the server's devices and properties,
/// reports changes on [events], and reconnects automatically when the
/// connection is lost. After a reconnect the session is resumed: the same
/// [IndiDevice] objects stay valid, properties are requested again, and a
/// [SessionResumed] event is emitted once they are restored.
///
/// Call [close] when the client is no longer needed.
///
/// {@category Client}
final class IndiClient {
  /// Creates a client for the INDI server at [host]:[port].
  ///
  /// Uses TCP on Android, iOS, desktop and the Dart VM. On the web, where
  /// TCP is not available, it connects to a WebSocket at `ws://host:port`,
  /// which needs a bridge such as websockify in front of indiserver; see
  /// [IndiClient.withTransport] and `WebSocketTransport` for more control.
  IndiClient({
    String host = 'localhost',
    int port = 7624,
    IndiClientOptions options = const IndiClientOptions(),
  }) : this.withTransport(defaultTransport(host, port), options: options);

  /// Creates a client that connects through [transport].
  ///
  /// [blobTransport] is used for the second connection when
  /// [IndiClientOptions.separateBlobConnection] is set; it defaults to
  /// [transport].
  IndiClient.withTransport(
    this.transport, {
    this.options = const IndiClientOptions(),
    IndiTransport? blobTransport,
  }) {
    _watchedDevices.addAll(options.watchDevices);
    _main = _supervisor(transport, isBlob: false);
    if (options.separateBlobConnection) {
      _blob = _supervisor(blobTransport ?? transport, isBlob: true);
    }
  }

  /// How the client reaches the server.
  final IndiTransport transport;

  /// The client configuration.
  final IndiClientOptions options;

  late final ConnectionSupervisor _main;
  ConnectionSupervisor? _blob;
  final CommandTracker _tracker = CommandTracker();
  final StreamController<IndiEvent> _events =
      StreamController<IndiEvent>.broadcast();
  final StreamController<IndiCommand> _commands =
      StreamController<IndiCommand>.broadcast();
  final Map<String, IndiDevice> _devices = {};
  final ListQueue<IndiMessage> _messages = ListQueue<IndiMessage>();
  final Set<String> _watchedDevices = {};
  final Set<(String, String)> _watchedProperties = {};
  final Map<(String, String?), BlobMode> _blobModes = {};
  final Map<String, Completer<void>> _pings = {};
  int _pingCounter = 0;
  bool _closed = false;

  /// Incremented on every reconnect; devices and properties remember the
  /// generation in which they were last defined.
  int _generation = 0;
  DateTime? _lostAt;
  DateTime? _reconnectedAt;
  int _resumeAttempts = 0;
  Timer? _settleTimer;
  DateTime? _settleStarted;

  ConnectionSupervisor _supervisor(
    IndiTransport transport, {
    required bool isBlob,
  }) =>
      ConnectionSupervisor(
        transport: transport,
        connectTimeout: options.connectTimeout,
        reconnect: options.reconnect,
        heartbeat: options.heartbeat,
        // The BLOB connection opens after the main one succeeded, so a
        // failure is likely transient: always retry it.
        retryInitialConnect: isBlob || options.retryInitialConnect,
        logger: Logger(isBlob ? 'indi.connection.blob' : 'indi.connection'),
        onCommand: (command) => _handleCommand(command, fromBlob: isBlob),
        onProtocolError: (error) => _emit(ProtocolErrorReceived(error)),
        onConnected: ({required isReconnect, required attempts}) => isBlob
            ? _onBlobConnected()
            : _onConnected(isReconnect: isReconnect, attempts: attempts),
        onConnectionLost: isBlob ? (_) {} : _onConnectionLost,
        onStateChanged: isBlob
            ? (state) => _log.fine('BLOB connection: $state')
            : (state) => _emit(ConnectionStateChanged(state)),
      );

  // -------------------------------------------------------------------------
  // Connection.
  // -------------------------------------------------------------------------

  /// The state of the connection to the server.
  IndiConnectionState get connectionState => _main.state;

  /// The connection state now and after every change. Emits the current
  /// state first, which suits Flutter's `StreamBuilder`.
  Stream<IndiConnectionState> get connectionStates =>
      _currentThen(() => connectionState, (event) {
        return event is ConnectionStateChanged ? event.state : null;
      });

  /// Whether the client is connected to the server.
  bool get isConnected => _main.state is IndiConnected;

  /// Whether [close] was called. A closed client can't be used anymore.
  bool get isClosed => _closed;

  /// Connects to the server and requests the properties of every device
  /// (or of the watched devices).
  ///
  /// Completes when connected; devices then appear asynchronously, so use
  /// [waitForDevice] to wait for one. Throws an [IndiConnectionException]
  /// if the server can't be reached. Once connected, the client reconnects
  /// automatically as configured in [IndiClientOptions.reconnect].
  Future<void> connect() async {
    _checkOpen();
    await _main.start();
    final blob = _blob;
    if (blob != null) {
      // The BLOB connection is secondary: it is retried in the background,
      // and only logged if reconnecting gives up. It never fails connect().
      unawaited(blob.start().catchError(
            (Object e) => _log.warning('BLOB connection failed: $e'),
          ));
    }
  }

  /// Disconnects from the server and stops reconnecting.
  ///
  /// Devices are removed, as the server state is unknown while
  /// disconnected. [connect] can be called again.
  Future<void> disconnect() async {
    if (_closed) return;
    _settleTimer?.cancel();
    await _blob?.stop();
    await _main.stop();
    _tracker.failAll(const IndiNotConnectedException('Disconnected'));
    _clearDevices();
  }

  /// Disconnects and releases every resource. Streams are closed and the
  /// client can't be used anymore.
  Future<void> close() async {
    if (_closed) return;
    // Set first, so everything that reacts to the disconnection can tell a
    // deliberate close from a lost connection.
    _closed = true;
    _settleTimer?.cancel();
    await _blob?.close();
    await _main.close();
    _tracker.failAll(const IndiClosedException('The client was closed'));
    for (final ping in _pings.values) {
      ping.completeError(const IndiClosedException('The client was closed'));
    }
    _pings.clear();
    _clearDevices();
    await _events.close();
    await _commands.close();
  }

  /// Measures the round-trip time to the server with a `pingRequest`.
  ///
  /// Needs indiserver 2.0 or later; older servers never answer, so this
  /// throws an [IndiTimeoutException] after [timeout].
  Future<Duration> ping({Duration timeout = const Duration(seconds: 5)}) async {
    _checkOpen();
    final uid = 'rtt${++_pingCounter}';
    final completer = _pings[uid] = Completer<void>();
    final stopwatch = clock.stopwatch()..start();
    try {
      _main.send(PingRequest(uid: uid));
      await completer.future.timeout(
        timeout,
        onTimeout: () => throw IndiTimeoutException(
          'No ping reply within $timeout',
          timeout,
        ),
      );
      return stopwatch.elapsed;
    } finally {
      _pings.remove(uid);
    }
  }

  // -------------------------------------------------------------------------
  // Devices.
  // -------------------------------------------------------------------------

  /// The devices currently known, by name.
  Map<String, IndiDevice> get devices => UnmodifiableMapView(_devices);

  /// The device called [name], or `null` if it is not known.
  IndiDevice? device(String name) => _devices[name];

  /// The devices whose driver implements [interface], like libindi's
  /// `getDevices(list, interface)`.
  ///
  /// The interfaces come from the `DRIVER_INFO` property, which is usually
  /// among the first properties a driver defines.
  Iterable<IndiDevice> devicesWith(DeviceInterface interface) =>
      _devices.values.where((device) => device.hasInterface(interface));

  /// Waits until the device called [name] is available and returns it.
  ///
  /// Returns at once if it already is. Throws an [IndiTimeoutException] if
  /// [timeout] expires first, or an [IndiClosedException] if the client is
  /// closed.
  Future<IndiDevice> waitForDevice(String name, {Duration? timeout}) {
    return _waitFor(
      () {
        final device = _devices[name];
        return device != null && device.isAvailable ? device : null;
      },
      timeout: timeout,
      description: 'device "$name"',
    );
  }

  /// Starts tracking the device called [name] in addition to the watched
  /// devices, and requests its properties if connected.
  ///
  /// When no device is watched (the default) every device is tracked
  /// anyway. Once any device or property is watched, only watched ones are
  /// tracked.
  void watchDevice(String name) {
    _checkOpen();
    if (!_watchedDevices.add(name)) return;
    if (isConnected) _main.send(GetProperties(device: name));
  }

  /// Starts tracking one property of a device, and requests it if
  /// connected. See [watchDevice].
  void watchProperty(String device, String property) {
    _checkOpen();
    if (!_watchedProperties.add((device, property))) return;
    if (isConnected) _main.send(GetProperties(device: device, name: property));
  }

  // -------------------------------------------------------------------------
  // Events and messages.
  // -------------------------------------------------------------------------

  /// Everything that happens on the client, as it happens.
  ///
  /// A broadcast stream: listen as many times as needed. Events are
  /// delivered asynchronously, after the client's model was updated.
  Stream<IndiEvent> get events => _events.stream;

  /// The events of type [E] only, such as `eventsOf<PropertyUpdated>()`.
  Stream<E> eventsOf<E extends IndiEvent>() =>
      events.where((event) => event is E).cast<E>();

  /// Every command received from the server, before it is applied to the
  /// model. Useful for logging and debugging.
  Stream<IndiCommand> get commands => _commands.stream;

  /// The most recent messages from the server and every device, oldest
  /// first. See [IndiClientOptions.messageHistory].
  List<IndiMessage> get messages => List.unmodifiable(_messages);

  // -------------------------------------------------------------------------
  // BLOBs and raw commands.
  // -------------------------------------------------------------------------

  /// Sets which BLOBs the server sends: for one [property] of [device], or
  /// for all of its BLOB properties when [property] is `null`.
  ///
  /// The server sends no BLOBs by default. The setting is remembered and
  /// restored after a reconnect. With
  /// [IndiClientOptions.separateBlobConnection], BLOBs arrive on the
  /// dedicated connection.
  ///
  /// Note that indiserver applies a setting without [property] to every
  /// device on the connection.
  Future<void> setBlobMode(
    BlobMode mode, {
    required String device,
    String? property,
  }) async {
    _checkOpen();
    _blobModes[(device, property)] = mode;
    _sendBlobMode(device, property, mode);
  }

  /// The BLOB mode set for [property] of [device] (or for the whole device
  /// when [property] is `null`), or [BlobMode.never] if none was set.
  BlobMode blobMode({required String device, String? property}) =>
      _blobModes[(device, property)] ??
      _blobModes[(device, null)] ??
      BlobMode.never;

  /// Sends a raw [command] to the server.
  ///
  /// Prefer the methods of [IndiDevice], which validate values and wait for
  /// answers. Throws an [IndiNotConnectedException] when not connected.
  void sendCommand(IndiCommand command) {
    _checkOpen();
    _main.send(command);
  }

  // -------------------------------------------------------------------------
  // Internals.
  // -------------------------------------------------------------------------

  void _checkOpen() {
    if (_closed) throw const IndiClosedException('The client was closed');
  }

  void _emit(IndiEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  void _onConnected({required bool isReconnect, required int attempts}) {
    // Devices left from an earlier connection (after reconnecting gave up
    // and connect() was called again) are reconciled like a reconnect.
    if (isReconnect || _devices.isNotEmpty) {
      _generation++;
      _reconnectedAt = clock.now();
      _resumeAttempts = attempts;
      _settleStarted = clock.now();
      _restartSettleTimer();
    }
    _requestProperties();
    if (_blob == null) {
      for (final MapEntry(key: (device, property), value: mode)
          in _blobModes.entries) {
        _sendBlobMode(device, property, mode);
      }
    }
  }

  void _onBlobConnected() {
    final blob = _blob!;
    _send(blob, const GetProperties());
    for (final MapEntry(key: (device, property), value: mode)
        in _blobModes.entries) {
      _sendBlobMode(device, property, mode);
    }
  }

  void _requestProperties() {
    if (_watchedDevices.isEmpty && _watchedProperties.isEmpty) {
      _send(_main, const GetProperties());
      return;
    }
    for (final device in _watchedDevices) {
      _send(_main, GetProperties(device: device));
    }
    for (final (device, property) in _watchedProperties) {
      if (_watchedDevices.contains(device)) continue;
      _send(_main, GetProperties(device: device, name: property));
    }
  }

  void _sendBlobMode(String device, String? property, BlobMode mode) {
    final blob = _blob;
    if (blob == null) {
      if (_main.state is IndiConnected) {
        _send(_main, EnableBlob(mode: mode, device: device, name: property));
      }
    } else if (blob.state is IndiConnected) {
      // The dedicated connection receives only BLOBs.
      final blobMode = mode == BlobMode.never ? BlobMode.never : BlobMode.only;
      _send(blob, EnableBlob(mode: blobMode, device: device, name: property));
    }
  }

  void _send(ConnectionSupervisor supervisor, IndiCommand command) {
    try {
      supervisor.send(command);
    } on IndiNotConnectedException catch (e) {
      _log.fine('Dropped ${command.runtimeType}: ${e.message}');
    }
  }

  void _onConnectionLost(Object error) {
    _lostAt ??= clock.now();
    _settleTimer?.cancel();
    _tracker.failAll(IndiConnectionLostException(
      'Connection lost before the command completed: $error',
    ));
  }

  bool _isWatched(String device, String? property) {
    if (_watchedDevices.isEmpty && _watchedProperties.isEmpty) return true;
    if (_watchedDevices.contains(device)) return true;
    if (property == null) {
      return _watchedProperties.any((watched) => watched.$1 == device);
    }
    return _watchedProperties.contains((device, property));
  }

  void _handleCommand(IndiCommand command, {required bool fromBlob}) {
    if (!_commands.isClosed && _commands.hasListener) _commands.add(command);
    switch (command) {
      case DefVector():
        if (!_isWatched(command.device, command.name)) return;
        _define(command);
      case SetVector():
        if (!_isWatched(command.device, command.name)) return;
        _update(command);
      case DelProperty():
        if (!_isWatched(command.device, command.name)) return;
        _delete(command);
      case MessageCommand(:final device):
        if (device != null && !_isWatched(device, null)) return;
        _addMessage(device, command.message, command.timestamp);
      case PingRequest():
        _send(fromBlob ? _blob! : _main, PingReply(uid: command.uid));
      case PingReply():
        _pings.remove(command.uid)?.complete();
      case NewVector() || GetProperties() || EnableBlob() || UnknownCommand():
        _log.fine('Ignored ${command.runtimeType} from the server');
    }
  }

  void _define(DefVector definition) {
    var device = _devices[definition.device];
    final isNewDevice = device == null;
    device ??=
        _devices[definition.device] = IndiDevice._(this, definition.device);
    device._generation = _generation;
    final property = propertyFromDefinition(definition);
    final previous = device._properties[property.name];
    device._properties[property.name] = property;
    device._propertyGenerations[property.name] = _generation;
    if (isNewDevice) _emit(DeviceAdded(device));
    if (previous == null) {
      _emit(PropertyDefined(device, property));
    } else if (previous.type != property.type) {
      _emit(PropertyRemoved(device, previous));
      _emit(PropertyDefined(device, property));
    } else {
      _emit(PropertyUpdated(device, property, previous));
    }
    _tracker.onUpdate(property, message: definition.message);
    _vectorMessage(definition.device, definition.message, definition.timestamp);
    if (definition is DefBlobVector) _resendBlobMode(definition);
    if (_settleStarted != null) _restartSettleTimer();
  }

  void _resendBlobMode(DefBlobVector definition) {
    final mode = _blobModes[(definition.device, definition.name)];
    if (mode != null) _sendBlobMode(definition.device, definition.name, mode);
  }

  void _update(SetVector update) {
    final device = _devices[update.device];
    final previous = device?._properties[update.name];
    if (device == null || previous == null) {
      _log.fine('Update for unknown property ${update.device}.${update.name}');
      return;
    }
    final property = applyUpdate(previous, update);
    if (property == null) {
      _emit(ProtocolErrorReceived(IndiProtocolException(
        '${update.runtimeType} for ${previous.type.wireName} property '
        '"${update.device}.${update.name}"',
      )));
      return;
    }
    device._properties[update.name] = property;
    _emit(PropertyUpdated(device, property, previous));
    _tracker.onUpdate(property, message: update.message);
    _vectorMessage(update.device, update.message, update.timestamp);
  }

  void _delete(DelProperty deletion) {
    final device = _devices[deletion.device];
    if (device == null) return;
    _vectorMessage(deletion.device, deletion.message, deletion.timestamp);
    final name = deletion.name;
    if (name == null) {
      _removeDevice(device);
      return;
    }
    final property = device._properties.remove(name);
    device._propertyGenerations.remove(name);
    _tracker.onRemoved(device.name, name);
    if (property != null) _emit(PropertyRemoved(device, property));
  }

  void _removeDevice(IndiDevice device) {
    _devices.remove(device.name);
    device._removed = true;
    _tracker.onRemoved(device.name);
    for (final property in device._properties.values.toList()) {
      _emit(PropertyRemoved(device, property));
    }
    _emit(DeviceRemoved(device));
  }

  void _clearDevices() {
    for (final device in _devices.values.toList()) {
      _removeDevice(device);
    }
    _lostAt = null;
    _settleStarted = null;
  }

  void _vectorMessage(String device, String? text, DateTime? timestamp) {
    if (text != null && text.isNotEmpty) _addMessage(device, text, timestamp);
  }

  void _addMessage(String? deviceName, String text, DateTime? timestamp) {
    final message =
        IndiMessage(device: deviceName, text: text, timestamp: timestamp);
    _appendMessage(_messages, message);
    final device = deviceName == null ? null : _devices[deviceName];
    if (device != null) _appendMessage(device._messages, message);
    _emit(MessageReceived(message, device));
  }

  void _appendMessage(ListQueue<IndiMessage> queue, IndiMessage message) {
    if (options.messageHistory <= 0) return;
    queue.addLast(message);
    while (queue.length > options.messageHistory) {
      queue.removeFirst();
    }
  }

  void _restartSettleTimer() {
    _settleTimer?.cancel();
    final started = _settleStarted;
    if (started == null) return;
    final remaining =
        options.resumeMaxSettleTime - clock.now().difference(started);
    final delay = remaining < options.resumeSettleTime
        ? (remaining.isNegative ? Duration.zero : remaining)
        : options.resumeSettleTime;
    _settleTimer = Timer(delay, _finishResume);
  }

  /// Removes what was not defined again since the reconnect, and reports
  /// the resumed session.
  void _finishResume() {
    _settleStarted = null;
    for (final device in _devices.values.toList()) {
      if (device._generation != _generation) {
        _removeDevice(device);
        continue;
      }
      for (final MapEntry(key: name, value: generation)
          in device._propertyGenerations.entries.toList()) {
        if (generation == _generation) continue;
        final property = device._properties.remove(name)!;
        device._propertyGenerations.remove(name);
        _tracker.onRemoved(device.name, name);
        _emit(PropertyRemoved(device, property));
      }
    }
    final lostAt = _lostAt;
    final reconnectedAt = _reconnectedAt ?? clock.now();
    _lostAt = null;
    _reconnectedAt = null;
    _emit(SessionResumed(
      downtime:
          lostAt == null ? Duration.zero : reconnectedAt.difference(lostAt),
      attempts: _resumeAttempts,
      devices: List.unmodifiable(_devices.values),
    ));
  }

  /// A stream that emits [current]() on listen, then every non-null result
  /// of [select] for later events, skipping repeated values.
  Stream<T> _currentThen<T>(
    T? Function() current,
    T? Function(IndiEvent event) select,
  ) {
    return Stream<T>.multi((controller) {
      Object? last = _none;
      void emit(T? value) {
        if (value == null || identical(value, last) || value == last) return;
        last = value;
        controller.add(value);
      }

      emit(current());
      if (_events.isClosed) {
        unawaited(controller.close());
        return;
      }
      final subscription = _events.stream.listen(
        (event) => emit(select(event)),
        onDone: controller.close,
      );
      controller
        ..onCancel = subscription.cancel
        ..onPause = subscription.pause
        ..onResume = subscription.resume;
    });
  }

  Future<T> _waitFor<T extends Object>(
    T? Function() check, {
    Duration? timeout,
    required String description,
  }) {
    final ready = check();
    if (ready != null) return Future.value(ready);
    if (_closed) {
      return Future.error(const IndiClosedException('The client was closed'));
    }
    final completer = Completer<T>();
    late final StreamSubscription<IndiEvent> subscription;
    Timer? timer;
    void finish() {
      timer?.cancel();
      unawaited(subscription.cancel());
    }

    subscription = _events.stream.listen(
      (_) {
        final value = check();
        if (value != null && !completer.isCompleted) {
          finish();
          completer.complete(value);
        }
      },
      onDone: () {
        timer?.cancel();
        if (!completer.isCompleted) {
          completer.completeError(
            const IndiClosedException('The client was closed'),
          );
        }
      },
    );
    if (timeout != null) {
      timer = Timer(timeout, () {
        if (completer.isCompleted) return;
        finish();
        completer.completeError(IndiTimeoutException(
          'Timed out after $timeout waiting for $description',
          timeout,
        ));
      });
    }
    return completer.future;
  }

  @override
  String toString() => 'IndiClient(${transport.description})';
}

const Object _none = Object();
