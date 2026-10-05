import 'dart:typed_data';

/// Structural equality for the values held by protocol and model objects:
/// lists and maps compare element-wise, and NaN equals NaN.
bool deepEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is double && b is double) return a == b || (a.isNaN && b.isNaN);
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  return a == b;
}

/// A hash code consistent with [deepEquals].
int deepHash(Object? value) => switch (value) {
      // Hashing every byte of a large BLOB would be slow.
      Uint8List() => value.length,
      List() => Object.hashAll(value.map(deepHash)),
      Map() => Object.hashAllUnordered(
          value.entries.map((e) => Object.hash(e.key, deepHash(e.value))),
        ),
      double() when value.isNaN => 0,
      _ => value.hashCode,
    };

/// Formats a field value for `toString`.
String describeValue(Object? value) => switch (value) {
      Uint8List() => '<${value.length} bytes>',
      String() => "'$value'",
      _ => '$value',
    };
