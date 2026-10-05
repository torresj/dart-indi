import 'dart:async';
import 'dart:typed_data';

import '../exceptions.dart';
import '../model/enums.dart';
import '../protocol/commands.dart';
import '../protocol/decoder.dart';
import '../protocol/encoder.dart';
import '../transport/in_memory_transport.dart';
import '../transport/transport.dart';

/// Decides how a [FakeIndiServer] answers a `new*Vector` command.
///
/// Return the commands to send back, or `null` for the default behavior
/// (apply the values and answer with state `Ok`).
///
/// {@category Testing}
typedef FakeCommandHandler = FutureOr<List<IndiCommand>?> Function(
  NewVector command,
  FakeIndiServer server,
);

/// An in-process INDI server for testing applications without hardware.
///
/// It plays the part of indiserver and its drivers: it answers
/// `getProperties` with the properties you [define], applies `new*Vector`
/// commands and answers with `set*Vector`, honors `enableBLOB`, and answers
/// pings. Connection failures can be simulated with [dropConnections] and
/// [refuseConnections].
///
/// ```dart
/// final server = FakeIndiServer()
///   ..define(DefSwitchVector(
///     device: 'Mount',
///     name: 'CONNECTION',
///     rule: SwitchRule.oneOfMany,
///     elements: const [
///       DefSwitch(name: 'CONNECT', state: SwitchState.off),
///       DefSwitch(name: 'DISCONNECT', state: SwitchState.on),
///     ],
///   ));
/// final client = IndiClient.withTransport(server.transport);
/// await client.connect();
/// ```
///
/// {@category Testing}
final class FakeIndiServer {
  /// Creates a server. [onNewVector] customizes how commands are answered.
  FakeIndiServer({this.onNewVector}) {
    transport = InMemoryTransport(onConnect: _accept);
  }

  /// The transport to give to `IndiClient.withTransport`.
  late final InMemoryTransport transport;

  /// Customizes how `new*Vector` commands are answered.
  FakeCommandHandler? onNewVector;

  /// Whether `pingRequest` is answered, like indiserver 2.x. Set to `false`
  /// to simulate an older server.
  bool answerPings = true;

  final Map<(String, String), DefVector> _definitions = {};
  final List<FakeServerConnection> _connections = [];
  final StreamController<IndiCommand> _received =
      StreamController<IndiCommand>.broadcast();

  /// Every command received from any client.
  Stream<IndiCommand> get received => _received.stream;

  /// The open connections.
  List<FakeServerConnection> get connections =>
      List.unmodifiable(_connections.where((c) => !c.isClosed));

  /// Whether new connections are refused, as if the server were down.
  bool get refuseConnections => transport.refuseConnections;
  set refuseConnections(bool value) => transport.refuseConnections = value;

  /// The current definition of [property] of [device], with the latest
  /// values applied.
  DefVector? definition(String device, String property) =>
      _definitions[(device, property)];

  /// The names of the devices defined.
  Set<String> get devices => {for (final key in _definitions.keys) key.$1};

  /// Defines (or redefines) a property and announces it to connected
  /// clients that asked for it.
  void define(DefVector definition) {
    _definitions[(definition.device, definition.name)] = definition;
    for (final connection in connections) {
      if (connection._wants(definition.device, definition.name)) {
        connection.send(definition);
      }
    }
  }

  /// Sends an update to connected clients and records the new values.
  void update(SetVector update) {
    final key = (update.device, update.name);
    final current = _definitions[key];
    if (current != null) _definitions[key] = _apply(current, update);
    for (final connection in connections) {
      if (!connection._wants(update.device, update.name)) continue;
      if (update is SetBlobVector) {
        if (connection.blobMode(update.device, update.name) == BlobMode.never) {
          continue;
        }
      } else if (connection.blobMode(update.device, update.name) ==
          BlobMode.only) {
        continue;
      }
      connection.send(update);
    }
  }

  /// Deletes a property, or a whole device when [property] is `null`, and
  /// tells connected clients.
  void delete(String device, [String? property]) {
    _definitions.removeWhere(
      (key, _) => key.$1 == device && (property == null || key.$2 == property),
    );
    for (final connection in connections) {
      if (connection._wants(device, property)) {
        connection.send(DelProperty(device: device, name: property));
      }
    }
  }

  /// Sends a message to connected clients.
  void message(String text, {String? device}) {
    for (final connection in connections) {
      if (device == null || connection._wants(device, null)) {
        connection.send(MessageCommand(device: device, message: text));
      }
    }
  }

  /// Closes every connection, as if the network failed. Clients see the
  /// connection lost and start reconnecting.
  Future<void> dropConnections() async {
    for (final connection in List.of(_connections)) {
      await connection.close();
    }
    _connections.clear();
  }

  /// Closes every connection and stops the server.
  Future<void> close() async {
    refuseConnections = true;
    await dropConnections();
    await _received.close();
  }

  void _accept(InMemoryConnection side) {
    final connection = FakeServerConnection._(this, side);
    _connections.add(connection);
  }

  Future<void> _handle(
    FakeServerConnection connection,
    IndiCommand command,
  ) async {
    if (!_received.isClosed) _received.add(command);
    switch (command) {
      case GetProperties(:final device, :final name):
        connection._interests.add((device, name));
        for (final definition in _definitions.values) {
          if ((device == null || definition.device == device) &&
              (name == null || definition.name == name)) {
            connection.send(definition);
          }
        }
      case EnableBlob(:final device, :final name, :final mode):
        connection._blobModes[(device, name)] = mode;
      case PingRequest(:final uid):
        if (answerPings) connection.send(PingReply(uid: uid));
      case NewVector():
        final custom = await onNewVector?.call(command, this);
        if (custom != null) {
          for (final reply in custom) {
            if (reply is SetVector) {
              update(reply);
            } else {
              connection.send(reply);
            }
          }
        } else {
          update(_defaultAnswer(command));
        }
      default:
        break;
    }
  }

  /// The update a well-behaved driver sends after accepting [command].
  SetVector _defaultAnswer(NewVector command) {
    final device = command.device;
    final name = command.name;
    final definition = _definitions[(device, name)];
    switch (command) {
      case NewSwitchVector(:final elements):
        // Apply the switch rule like libindi's IUUpdateSwitch.
        var states = {for (final e in elements) e.name: e.state};
        if (definition is DefSwitchVector &&
            definition.rule != SwitchRule.anyOfMany &&
            elements.any((e) => e.state == SwitchState.on)) {
          final on = elements.firstWhere((e) => e.state == SwitchState.on);
          states = {
            for (final e in definition.elements)
              e.name: e.name == on.name ? SwitchState.on : SwitchState.off,
          };
        }
        return SetSwitchVector(
          device: device,
          name: name,
          state: PropertyState.ok,
          elements: [
            for (final MapEntry(:key, :value) in states.entries)
              OneSwitch(name: key, state: value),
          ],
        );
      case NewNumberVector(:final elements):
        return SetNumberVector(
          device: device,
          name: name,
          state: PropertyState.ok,
          elements: elements,
        );
      case NewTextVector(:final elements):
        return SetTextVector(
          device: device,
          name: name,
          state: PropertyState.ok,
          elements: elements,
        );
      case NewBlobVector():
        return SetBlobVector(
          device: device,
          name: name,
          state: PropertyState.ok,
          elements: const [],
        );
    }
  }

  static DefVector _apply(DefVector definition, SetVector update) {
    final state = update.state ?? definition.state;
    switch ((definition, update)) {
      case (final DefTextVector d, final SetTextVector u):
        final values = {for (final e in u.elements) e.name: e.value};
        return DefTextVector(
          device: d.device,
          name: d.name,
          label: d.label,
          group: d.group,
          state: state,
          perm: d.perm,
          timeout: d.timeout,
          elements: [
            for (final e in d.elements)
              DefText(
                name: e.name,
                label: e.label,
                value: values[e.name] ?? e.value,
              ),
          ],
        );
      case (final DefNumberVector d, final SetNumberVector u):
        final values = {for (final e in u.elements) e.name: e};
        return DefNumberVector(
          device: d.device,
          name: d.name,
          label: d.label,
          group: d.group,
          state: state,
          perm: d.perm,
          timeout: d.timeout,
          elements: [
            for (final e in d.elements)
              DefNumber(
                name: e.name,
                label: e.label,
                format: e.format,
                min: values[e.name]?.min ?? e.min,
                max: values[e.name]?.max ?? e.max,
                step: values[e.name]?.step ?? e.step,
                value: values[e.name]?.value ?? e.value,
              ),
          ],
        );
      case (final DefSwitchVector d, final SetSwitchVector u):
        final values = {for (final e in u.elements) e.name: e.state};
        return DefSwitchVector(
          device: d.device,
          name: d.name,
          label: d.label,
          group: d.group,
          state: state,
          perm: d.perm,
          rule: d.rule,
          timeout: d.timeout,
          elements: [
            for (final e in d.elements)
              DefSwitch(
                name: e.name,
                label: e.label,
                state: values[e.name] ?? e.state,
              ),
          ],
        );
      case (final DefLightVector d, final SetLightVector u):
        final values = {for (final e in u.elements) e.name: e.state};
        return DefLightVector(
          device: d.device,
          name: d.name,
          label: d.label,
          group: d.group,
          state: state,
          elements: [
            for (final e in d.elements)
              DefLight(
                name: e.name,
                label: e.label,
                state: values[e.name] ?? e.state,
              ),
          ],
        );
      default:
        return definition;
    }
  }
}

/// One client connection to a [FakeIndiServer].
///
/// {@category Testing}
final class FakeServerConnection {
  FakeServerConnection._(this.server, this._side) {
    final decoder = IndiStreamDecoder(
      onCommand: (command) {
        _pending = _pending.then((_) => server._handle(this, command));
      },
      onError: protocolErrors.add,
    );
    _side.input.listen(decoder.add, onError: (Object _) {});
  }

  /// The server this connection belongs to.
  final FakeIndiServer server;
  final IndiConnection _side;
  Future<void> _pending = Future<void>.value();
  final Set<(String?, String?)> _interests = {};
  final Map<(String, String?), BlobMode> _blobModes = {};

  /// Protocol errors found in what the client sent.
  final List<IndiProtocolException> protocolErrors = [];

  /// Whether the connection is closed.
  bool get isClosed => (_side as InMemoryConnection).isClosed;

  /// The BLOB mode the client set for [property] of [device] on this
  /// connection.
  BlobMode blobMode(String device, String property) =>
      _blobModes[(device, property)] ??
      _blobModes[(device, null)] ??
      BlobMode.never;

  bool _wants(String device, String? property) => _interests.any(
        (interest) =>
            (interest.$1 == null || interest.$1 == device) &&
            (interest.$2 == null ||
                property == null ||
                interest.$2 == property),
      );

  /// Sends [command] to the client on this connection only.
  void send(IndiCommand command) {
    if (isClosed) return;
    for (final chunk in encodeIndiCommandChunks(command)) {
      _side.add(chunk);
    }
  }

  /// Sends raw bytes, for example malformed XML.
  void sendRaw(List<int> bytes) =>
      _side.add(bytes is Uint8List ? bytes : Uint8List.fromList(bytes));

  /// Closes the connection.
  Future<void> close() => _side.close();
}
