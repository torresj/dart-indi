/// The state of an INDI property, as reported by the driver.
///
/// Clients usually render it as a colored indicator: grey for [idle], green
/// for [ok], yellow for [busy] and red for [alert].
///
/// {@category Model}
enum PropertyState {
  /// The property is not active.
  idle('Idle'),

  /// The last operation on the property completed successfully.
  ok('Ok'),

  /// An operation on the property is in progress.
  busy('Busy'),

  /// The last operation on the property failed or needs attention.
  alert('Alert');

  const PropertyState(this.wireValue);

  /// The value used for this state in the INDI XML protocol.
  final String wireValue;

  /// Parses an INDI state value, ignoring case and surrounding whitespace.
  ///
  /// Returns `null` if [value] is not a known state.
  static PropertyState? tryParse(String? value) =>
      _parseWire(values, value, (s) => s.wireValue);
}

/// The permission hint of an INDI property.
///
/// {@category Model}
enum PropertyPermission {
  /// The client may only read the property.
  readOnly('ro'),

  /// The client may only write the property.
  writeOnly('wo'),

  /// The client may read and write the property.
  readWrite('rw');

  const PropertyPermission(this.wireValue);

  /// The value used for this permission in the INDI XML protocol.
  final String wireValue;

  /// Whether a client is allowed to read the property's values.
  bool get canRead => this != writeOnly;

  /// Whether a client is allowed to send new values for the property.
  bool get canWrite => this != readOnly;

  /// Parses an INDI permission value, ignoring case and surrounding
  /// whitespace.
  ///
  /// Returns `null` if [value] is not a known permission.
  static PropertyPermission? tryParse(String? value) =>
      _parseWire(values, value, (p) => p.wireValue);
}

/// The rule that constrains which switches of a switch property can be on.
///
/// {@category Model}
enum SwitchRule {
  /// Exactly one switch is on at any time, like radio buttons.
  oneOfMany('OneOfMany'),

  /// At most one switch is on; all of them may be off.
  atMostOne('AtMostOne'),

  /// Any number of switches may be on, like check boxes.
  anyOfMany('AnyOfMany');

  const SwitchRule(this.wireValue);

  /// The value used for this rule in the INDI XML protocol.
  final String wireValue;

  /// Parses an INDI switch rule, ignoring case and surrounding whitespace.
  ///
  /// Returns `null` if [value] is not a known rule.
  static SwitchRule? tryParse(String? value) =>
      _parseWire(values, value, (r) => r.wireValue);
}

/// The state of a single switch.
///
/// {@category Model}
enum SwitchState {
  /// The switch is off.
  off('Off'),

  /// The switch is on.
  on('On');

  const SwitchState(this.wireValue);

  /// The value used for this state in the INDI XML protocol.
  final String wireValue;

  /// Whether this state is [on].
  bool get isOn => this == on;

  /// Returns [on] if [value] is `true`, [off] otherwise.
  static SwitchState fromBool(bool value) => value ? on : off;

  /// Parses an INDI switch state, ignoring case and surrounding whitespace.
  ///
  /// Returns `null` if [value] is not a known state.
  static SwitchState? tryParse(String? value) =>
      _parseWire(values, value, (s) => s.wireValue);
}

/// Controls whether the server sends BLOB (binary) data to a connection.
///
/// See `enableBLOB` in the INDI protocol.
///
/// {@category Model}
enum BlobMode {
  /// Never send BLOBs. This is the server default for every connection.
  never('Never'),

  /// Send BLOBs along with all other traffic.
  also('Also'),

  /// Send only BLOBs and no other traffic.
  ///
  /// Useful for a dedicated connection that downloads images, so they never
  /// delay control traffic on the main connection.
  only('Only');

  const BlobMode(this.wireValue);

  /// The value used for this mode in the INDI XML protocol.
  final String wireValue;

  /// Parses an INDI BLOB mode, ignoring case and surrounding whitespace.
  ///
  /// Returns `null` if [value] is not a known mode.
  static BlobMode? tryParse(String? value) =>
      _parseWire(values, value, (m) => m.wireValue);
}

/// The type of an INDI property (a "vector" in protocol terms).
///
/// {@category Model}
enum PropertyType {
  /// A vector of text elements.
  text('Text'),

  /// A vector of number elements.
  number('Number'),

  /// A vector of switch elements.
  switches('Switch'),

  /// A vector of read-only light (status) elements.
  light('Light'),

  /// A vector of BLOB (binary) elements.
  blob('BLOB');

  const PropertyType(this.wireName);

  /// The name used for this type in INDI element names, such as the
  /// `Number` in `defNumberVector`.
  final String wireName;
}

T? _parseWire<T>(List<T> values, String? raw, String Function(T) wire) {
  if (raw == null) return null;
  final value = raw.trim().toLowerCase();
  for (final candidate in values) {
    if (wire(candidate).toLowerCase() == value) return candidate;
  }
  return null;
}
