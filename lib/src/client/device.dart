part of 'indi_client.dart';

/// Information about the driver of a device, from its `DRIVER_INFO`
/// property.
///
/// {@category Client}
@immutable
final class DriverInfo {
  /// Creates driver information.
  const DriverInfo({
    required this.name,
    required this.executable,
    required this.version,
    required this.interfaceMask,
  });

  /// The driver's display name, such as `Telescope Simulator`.
  final String name;

  /// The driver executable, such as `indi_simulator_telescope`.
  final String executable;

  /// The driver version.
  final String version;

  /// The raw `DRIVER_INTERFACE` bit mask.
  final int interfaceMask;

  /// The kinds of device the driver implements.
  Set<DeviceInterface> get interfaces =>
      DeviceInterface.fromMask(interfaceMask);

  @override
  bool operator ==(Object other) =>
      other is DriverInfo &&
      other.name == name &&
      other.executable == executable &&
      other.version == version &&
      other.interfaceMask == interfaceMask;

  @override
  int get hashCode => Object.hash(name, executable, version, interfaceMask);

  @override
  String toString() => 'DriverInfo($name, $executable $version, '
      'interfaces: ${interfaces.map((i) => i.name).join(', ')})';
}

/// A device on an INDI server, such as a mount, a camera or a focuser.
///
/// Devices are created by the [IndiClient] when the server defines their
/// first property; get them with [IndiClient.device] or
/// [IndiClient.waitForDevice]. A device object stays valid across
/// reconnections, so it can be kept in application state.
///
/// Reading values:
///
/// ```dart
/// final coords = mount.getNumber('EQUATORIAL_EOD_COORD');
/// print(coords?['RA']?.formattedValue);
/// mount.watch<NumberProperty>('EQUATORIAL_EOD_COORD').listen(print);
/// ```
///
/// Changing values (each call completes when the driver confirms):
///
/// ```dart
/// await mount.sendNumbers('EQUATORIAL_EOD_COORD', {'RA': 5.5, 'DEC': -5.4});
/// await mount.setSwitch('TELESCOPE_PARK', 'PARK');
/// ```
///
/// For common device types, the typed wrappers (`Telescope`, `Camera`,
/// `Focuser`, …) offer higher-level methods.
///
/// {@category Client}
final class IndiDevice {
  IndiDevice._(this.client, this.name);

  /// The client this device belongs to.
  final IndiClient client;

  /// The device name, unique on the server.
  final String name;

  final Map<String, IndiProperty> _properties = {};
  final Map<String, int> _propertyGenerations = {};
  final ListQueue<IndiMessage> _messages = ListQueue<IndiMessage>();
  int _generation = 0;
  bool _removed = false;

  /// Whether the device can be used now: the client is connected and the
  /// device was defined in the current session.
  ///
  /// `false` while the connection is down or being resumed, and after the
  /// device was removed.
  bool get isAvailable =>
      !_removed && client.isConnected && _generation == client._generation;

  /// Whether the device was removed from the server. A removed device
  /// never becomes available again; a new [IndiDevice] is created if the
  /// driver defines it again.
  bool get isRemoved => _removed;

  // -------------------------------------------------------------------------
  // Properties.
  // -------------------------------------------------------------------------

  /// The current properties, by name, in definition order.
  Map<String, IndiProperty> get properties => UnmodifiableMapView(_properties);

  /// The property called [propertyName], or `null` if there is none.
  IndiProperty? operator [](String propertyName) => _properties[propertyName];

  /// The number property called [propertyName], or `null` if there is no
  /// such number property.
  NumberProperty? getNumber(String propertyName) => _typed(propertyName);

  /// The text property called [propertyName], or `null`.
  TextProperty? getText(String propertyName) => _typed(propertyName);

  /// The switch property called [propertyName], or `null`.
  SwitchProperty? getSwitch(String propertyName) => _typed(propertyName);

  /// The light property called [propertyName], or `null`.
  LightProperty? getLight(String propertyName) => _typed(propertyName);

  /// The BLOB property called [propertyName], or `null`.
  BlobProperty? getBlob(String propertyName) => _typed(propertyName);

  P? _typed<P extends IndiProperty>(String propertyName) {
    final property = _properties[propertyName];
    return property is P ? property : null;
  }

  /// The property groups, in the order they first appear. User interfaces
  /// usually show one tab per group.
  List<String> get groups => {
        for (final property in _properties.values) property.group,
      }.toList();

  /// The properties of [group], in definition order.
  Iterable<IndiProperty> propertiesIn(String group) =>
      _properties.values.where((property) => property.group == group);

  /// The most recent messages about this device, oldest first.
  List<IndiMessage> get messages => List.unmodifiable(_messages);

  /// Information about the driver, from `DRIVER_INFO`, or `null` if the
  /// driver did not define it.
  DriverInfo? get driverInfo {
    final info = getText('DRIVER_INFO');
    if (info == null) return null;
    return DriverInfo(
      name: info.valueOf('DRIVER_NAME') ?? name,
      executable: info.valueOf('DRIVER_EXEC') ?? '',
      version: info.valueOf('DRIVER_VERSION') ?? '',
      interfaceMask:
          int.tryParse(info.valueOf('DRIVER_INTERFACE')?.trim() ?? '') ?? 0,
    );
  }

  /// The kinds of device the driver implements. Empty until `DRIVER_INFO`
  /// is defined.
  Set<DeviceInterface> get interfaces => driverInfo?.interfaces ?? const {};

  /// Whether the driver implements [interface].
  bool hasInterface(DeviceInterface interface) =>
      (driverInfo?.interfaceMask ?? 0) & interface.mask != 0;

  /// Whether the driver is connected to its hardware: the `CONNECT` switch
  /// of the standard `CONNECTION` property is on.
  bool get isConnected => getSwitch('CONNECTION')?.isOn('CONNECT') ?? false;

  // -------------------------------------------------------------------------
  // Streams.
  // -------------------------------------------------------------------------

  /// The client events that concern this device.
  Stream<IndiEvent> get events => client.events.where(
        (event) => switch (event) {
          DeviceAdded(:final device) ||
          DeviceRemoved(:final device) ||
          PropertyDefined(:final device) ||
          PropertyUpdated(:final device) ||
          PropertyRemoved(:final device) =>
            device.name == name,
          MessageReceived(:final message) => message.device == name,
          _ => false,
        },
      );

  /// The events of type [E] that concern this device, such as
  /// `eventsOf<PropertyUpdated>()`.
  Stream<E> eventsOf<E extends IndiEvent>() =>
      events.where((event) => event is E).cast<E>();

  /// The property called [propertyName] now and after every change.
  ///
  /// Emits the current value first, if the property exists, then each new
  /// snapshot. Keeps working if the property is deleted and defined again.
  /// Ideal for Flutter's `StreamBuilder`:
  ///
  /// ```dart
  /// StreamBuilder<NumberProperty>(
  ///   stream: camera.watch<NumberProperty>('CCD_TEMPERATURE'),
  ///   builder: (context, snapshot) => Text(
  ///     snapshot.data?['CCD_TEMPERATURE_VALUE']?.formattedValue ?? '…',
  ///   ),
  /// )
  /// ```
  Stream<P> watch<P extends IndiProperty>(String propertyName) =>
      client._currentThen<P>(
        () {
          final property = _properties[propertyName];
          return !_removed && property is P ? property : null;
        },
        (event) => switch (event) {
          PropertyDefined(:final device, :final P property) ||
          PropertyUpdated(:final device, :final P property)
              when device.name == name && property.name == propertyName =>
            property,
          _ => null,
        },
      );

  /// Waits until the property called [propertyName] is defined in the
  /// current session and returns it.
  ///
  /// Many properties only appear after the device is connected, so use this
  /// after [connect]. Throws an [IndiTimeoutException] if [timeout] expires
  /// first.
  Future<P> waitForProperty<P extends IndiProperty>(
    String propertyName, {
    Duration? timeout,
  }) {
    return client._waitFor<P>(
      () {
        final property = _properties[propertyName];
        return property is P &&
                client.isConnected &&
                _propertyGenerations[propertyName] == client._generation
            ? property
            : null;
      },
      timeout: timeout,
      description: 'property "$name.$propertyName"',
    );
  }

  // -------------------------------------------------------------------------
  // Commands.
  // -------------------------------------------------------------------------

  /// Asks the driver to change the numbers of [propertyName].
  ///
  /// Elements not in [values] keep their current values, since many drivers
  /// expect the whole vector. Completes with the property as confirmed by
  /// the driver, according to [completion]; see [CommandCompletion].
  ///
  /// Throws an [IndiNotFoundException], [IndiPermissionException] or
  /// [IndiValidationException] for invalid requests (before sending), an
  /// [IndiPropertyAlertException] if the driver rejects the change, and an
  /// [IndiTimeoutException] if [timeout] (default
  /// [IndiClientOptions.commandTimeout]) expires.
  Future<NumberProperty> sendNumbers(
    String propertyName,
    Map<String, num> values, {
    CommandCompletion completion = CommandCompletion.nextUpdate,
    Duration? timeout,
  }) {
    return _sendNew<NumberProperty>(
      propertyName,
      completion: completion,
      timeout: timeout,
      build: (property) {
        _checkElements(property, values.keys);
        if (client.options.validateValues) {
          for (final MapEntry(key: elementName, value: value)
              in values.entries) {
            final element = property.element(elementName);
            if (element.hasRange &&
                (value < element.min || value > element.max)) {
              throw IndiValidationException(
                '$value is outside the range [${element.min}, ${element.max}] '
                'of "$name.$propertyName.$elementName"',
              );
            }
          }
        }
        return NewNumberVector(
          device: name,
          name: propertyName,
          elements: [
            for (final element in property.elements)
              OneNumber(
                name: element.name,
                value: (values[element.name] ?? element.value).toDouble(),
              ),
          ],
        );
      },
      matches: (update) => values.entries.every((entry) {
        final element = update[entry.key];
        if (element == null) return false;
        final tolerance = math.max(
          element.step / 2,
          1e-9 * math.max(1, entry.value.abs()),
        );
        return (element.value - entry.value).abs() <= tolerance;
      }),
    );
  }

  /// Asks the driver to change one number of [propertyName]. See
  /// [sendNumbers].
  Future<NumberProperty> sendNumber(
    String propertyName,
    String elementName,
    num value, {
    CommandCompletion completion = CommandCompletion.nextUpdate,
    Duration? timeout,
  }) =>
      sendNumbers(
        propertyName,
        {elementName: value},
        completion: completion,
        timeout: timeout,
      );

  /// Asks the driver to change the texts of [propertyName].
  ///
  /// Elements not in [values] keep their current values. See [sendNumbers]
  /// for completion and errors.
  Future<TextProperty> sendTexts(
    String propertyName,
    Map<String, String> values, {
    CommandCompletion completion = CommandCompletion.nextUpdate,
    Duration? timeout,
  }) {
    return _sendNew<TextProperty>(
      propertyName,
      completion: completion,
      timeout: timeout,
      build: (property) {
        _checkElements(property, values.keys);
        return NewTextVector(
          device: name,
          name: propertyName,
          elements: [
            for (final element in property.elements)
              OneText(
                name: element.name,
                value: values[element.name] ?? element.value,
              ),
          ],
        );
      },
      matches: (update) => values.entries
          .every((entry) => update[entry.key]?.value == entry.value),
    );
  }

  /// Asks the driver to change one text of [propertyName]. See [sendTexts].
  Future<TextProperty> sendText(
    String propertyName,
    String elementName,
    String value, {
    CommandCompletion completion = CommandCompletion.nextUpdate,
    Duration? timeout,
  }) =>
      sendTexts(
        propertyName,
        {elementName: value},
        completion: completion,
        timeout: timeout,
      );

  /// Asks the driver to change switches of [propertyName], respecting its
  /// rule.
  ///
  /// For [SwitchRule.oneOfMany] and [SwitchRule.atMostOne] properties, the
  /// switch turned on is sent together with all the others turned off.
  /// Exactly one switch must be on for [SwitchRule.oneOfMany], and at most
  /// one for [SwitchRule.atMostOne]. For [SwitchRule.anyOfMany] properties
  /// only the given switches are sent.
  ///
  /// See [sendNumbers] for completion and errors.
  Future<SwitchProperty> sendSwitches(
    String propertyName,
    Map<String, bool> values, {
    CommandCompletion completion = CommandCompletion.nextUpdate,
    Duration? timeout,
  }) {
    return _sendNew<SwitchProperty>(
      propertyName,
      completion: completion,
      timeout: timeout,
      build: (property) {
        _checkElements(property, values.keys);
        final onCount = values.values.where((on) => on).length;
        final validate = client.options.validateValues;
        if (validate && property.rule == SwitchRule.oneOfMany && onCount != 1) {
          throw IndiValidationException(
            'Exactly one switch of "$name.$propertyName" must be on '
            '(rule OneOfMany)',
          );
        }
        if (validate && property.rule == SwitchRule.atMostOne && onCount > 1) {
          throw IndiValidationException(
            'At most one switch of "$name.$propertyName" can be on '
            '(rule AtMostOne)',
          );
        }
        final exclusive = property.rule != SwitchRule.anyOfMany && onCount == 1;
        return NewSwitchVector(
          device: name,
          name: propertyName,
          elements: exclusive
              ? [
                  for (final element in property.elements)
                    OneSwitch(
                      name: element.name,
                      state: SwitchState.fromBool(values[element.name] == true),
                    ),
                ]
              : [
                  for (final MapEntry(key: elementName, value: on)
                      in values.entries)
                    OneSwitch(
                      name: elementName,
                      state: SwitchState.fromBool(on),
                    ),
                ],
        );
      },
      matches: (update) => values.entries
          .every((entry) => update[entry.key]?.isOn == entry.value),
    );
  }

  /// Turns the switch [elementName] of [propertyName] on (or off when [on]
  /// is `false`), respecting the property's rule. See [sendSwitches].
  ///
  /// ```dart
  /// await mount.setSwitch('TELESCOPE_TRACK_STATE', 'TRACK_ON');
  /// ```
  Future<SwitchProperty> setSwitch(
    String propertyName,
    String elementName, {
    bool on = true,
    CommandCompletion completion = CommandCompletion.nextUpdate,
    Duration? timeout,
  }) =>
      sendSwitches(
        propertyName,
        {elementName: on},
        completion: completion,
        timeout: timeout,
      );

  /// Uploads binary data to the BLOB elements of [propertyName], for
  /// drivers that accept files.
  ///
  /// Completes once the data is written by default: indiserver only
  /// forwards the driver's acknowledgement (a `setBLOBVector`) to clients
  /// that enabled BLOBs, so waiting for it could take forever. Pass another
  /// [completion] after enabling BLOBs with [setBlobMode] to wait for it.
  /// See [sendNumbers] for errors.
  Future<BlobProperty> sendBlobs(
    String propertyName,
    Map<String, IndiBlob> values, {
    CommandCompletion completion = CommandCompletion.sent,
    Duration? timeout,
  }) {
    return _sendNew<BlobProperty>(
      propertyName,
      completion: completion,
      timeout: timeout,
      build: (property) {
        _checkElements(property, values.keys);
        return NewBlobVector(
          device: name,
          name: propertyName,
          elements: [
            for (final MapEntry(key: elementName, value: blob)
                in values.entries)
              OneBlob(
                name: elementName,
                format: blob.format,
                data: blob.bytes,
                size: blob.size,
              ),
          ],
        );
      },
      matches: (_) => false,
    );
  }

  /// Connects the driver to its hardware, using the standard `CONNECTION`
  /// property, and completes when the driver confirms.
  ///
  /// Throws an [IndiPropertyAlertException] with the driver's explanation
  /// if the hardware can't be reached.
  Future<void> connect({Duration? timeout}) =>
      setSwitch('CONNECTION', 'CONNECT', timeout: timeout);

  /// Disconnects the driver from its hardware. See [connect].
  Future<void> disconnect({Duration? timeout}) =>
      setSwitch('CONNECTION', 'DISCONNECT', timeout: timeout);

  /// Sets which BLOBs the server sends for this device: for one
  /// [property], or for all of its BLOB properties. See
  /// [IndiClient.setBlobMode].
  Future<void> setBlobMode(BlobMode mode, {String? property}) =>
      client.setBlobMode(mode, device: name, property: property);

  void _checkElements(IndiProperty property, Iterable<String> names) {
    for (final elementName in names) {
      if (property[elementName] == null) {
        throw IndiValidationException(
          'Property "$name.${property.name}" has no element "$elementName"',
        );
      }
    }
  }

  Future<P> _sendNew<P extends IndiProperty>(
    String propertyName, {
    required NewVector Function(P property) build,
    required bool Function(P update) matches,
    required CommandCompletion completion,
    required Duration? timeout,
  }) async {
    client._checkOpen();
    final current = _properties[propertyName];
    if (current == null) {
      throw IndiNotFoundException(
        'Device "$name" has no property "$propertyName"',
      );
    }
    if (current is! P) {
      throw IndiValidationException(
        '"$name.$propertyName" is a ${current.type.wireName} property',
      );
    }
    if (client.options.validateValues && !current.permission.canWrite) {
      throw IndiPermissionException('"$name.$propertyName" is read-only');
    }
    final command = build(current);
    client._main.send(command);

    // Show the change as in progress until the driver answers.
    final busy = withState(current, PropertyState.busy);
    if (!identical(busy, current)) {
      _properties[propertyName] = busy;
      client._emit(PropertyUpdated(this, busy, current));
    }
    if (completion == CommandCompletion.sent) return busy as P;

    final result = await client._tracker.track(
      device: name,
      property: propertyName,
      completion: completion,
      timeout: timeout ?? client.options.commandTimeout,
      matches: (update) => update is P && matches(update),
    );
    if (result is P) return result;
    throw IndiProtocolException(
      '"$name.$propertyName" was redefined as a ${result.type.wireName} '
      'property',
    );
  }

  @override
  String toString() => 'IndiDevice($name)';
}
