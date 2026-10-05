/// Conversions between protocol commands and model snapshots. Internal.
library;

import '../protocol/commands.dart';
import 'blob.dart';
import 'enums.dart';
import 'properties.dart';

/// Builds the snapshot described by a `def*Vector` command.
IndiProperty propertyFromDefinition(DefVector definition) {
  final d = definition;
  final timeout = d.timeout ?? 0;
  return switch (d) {
    DefTextVector() => TextProperty(
        device: d.device,
        name: d.name,
        label: d.label,
        group: d.group ?? '',
        state: d.state,
        permission: d.perm,
        timeout: timeout,
        timestamp: d.timestamp,
        elements: [
          for (final e in d.elements)
            TextElement(name: e.name, label: e.label, value: e.value),
        ],
      ),
    DefNumberVector() => NumberProperty(
        device: d.device,
        name: d.name,
        label: d.label,
        group: d.group ?? '',
        state: d.state,
        permission: d.perm,
        timeout: timeout,
        timestamp: d.timestamp,
        elements: [
          for (final e in d.elements)
            NumberElement(
              name: e.name,
              label: e.label,
              value: e.value,
              min: e.min,
              max: e.max,
              step: e.step,
              format: e.format,
            ),
        ],
      ),
    DefSwitchVector() => SwitchProperty(
        device: d.device,
        name: d.name,
        label: d.label,
        group: d.group ?? '',
        state: d.state,
        permission: d.perm,
        timeout: timeout,
        timestamp: d.timestamp,
        rule: d.rule,
        elements: [
          for (final e in d.elements)
            SwitchElement(name: e.name, label: e.label, state: e.state),
        ],
      ),
    DefLightVector() => LightProperty(
        device: d.device,
        name: d.name,
        label: d.label,
        group: d.group ?? '',
        state: d.state,
        timestamp: d.timestamp,
        elements: [
          for (final e in d.elements)
            LightElement(name: e.name, label: e.label, state: e.state),
        ],
      ),
    DefBlobVector() => BlobProperty(
        device: d.device,
        name: d.name,
        label: d.label,
        group: d.group ?? '',
        state: d.state,
        permission: d.perm,
        timeout: timeout,
        timestamp: d.timestamp,
        elements: [
          for (final e in d.elements) BlobElement(name: e.name, label: e.label),
        ],
      ),
  };
}

/// Applies a `set*Vector` update to [property].
///
/// Returns `null` if the update does not match the property's type.
/// Elements the property does not have are ignored, and absent optional
/// attributes keep their previous values.
IndiProperty? applyUpdate(IndiProperty property, SetVector update) {
  final state = update.state ?? property.state;
  final timeout = update.timeout ?? property.timeout;
  final timestamp = update.timestamp ?? property.timestamp;
  switch ((property, update)) {
    case (final TextProperty p, final SetTextVector u):
      final values = {for (final e in u.elements) e.name: e};
      return _copyText(
        p,
        state: state,
        timeout: timeout,
        timestamp: timestamp,
        elements: [
          for (final e in p.elements)
            if (values[e.name] case final v?)
              TextElement(name: e.name, label: e.label, value: v.value)
            else
              e,
        ],
      );
    case (final NumberProperty p, final SetNumberVector u):
      final values = {for (final e in u.elements) e.name: e};
      return _copyNumber(
        p,
        state: state,
        timeout: timeout,
        timestamp: timestamp,
        elements: [
          for (final e in p.elements)
            if (values[e.name] case final v?)
              NumberElement(
                name: e.name,
                label: e.label,
                value: v.value,
                min: v.min ?? e.min,
                max: v.max ?? e.max,
                step: v.step ?? e.step,
                format: e.format,
              )
            else
              e,
        ],
      );
    case (final SwitchProperty p, final SetSwitchVector u):
      final values = {for (final e in u.elements) e.name: e};
      return _copySwitch(
        p,
        state: state,
        timeout: timeout,
        timestamp: timestamp,
        elements: [
          for (final e in p.elements)
            if (values[e.name] case final v?)
              SwitchElement(name: e.name, label: e.label, state: v.state)
            else
              e,
        ],
      );
    case (final LightProperty p, final SetLightVector u):
      final values = {for (final e in u.elements) e.name: e};
      return _copyLight(
        p,
        state: state,
        timestamp: timestamp,
        elements: [
          for (final e in p.elements)
            if (values[e.name] case final v?)
              LightElement(name: e.name, label: e.label, state: v.state)
            else
              e,
        ],
      );
    case (final BlobProperty p, final SetBlobVector u):
      final values = {for (final e in u.elements) e.name: e};
      return _copyBlob(
        p,
        state: state,
        timeout: timeout,
        timestamp: timestamp,
        elements: [
          for (final e in p.elements)
            if (values[e.name] case final v?)
              BlobElement(
                name: e.name,
                label: e.label,
                blob: IndiBlob(v.data, format: v.format, size: v.size),
              )
            else
              e,
        ],
      );
    default:
      return null;
  }
}

/// Returns [property] with its state replaced by [state].
IndiProperty withState(IndiProperty property, PropertyState state) {
  if (property.state == state) return property;
  return switch (property) {
    final TextProperty p => _copyText(p, state: state),
    final NumberProperty p => _copyNumber(p, state: state),
    final SwitchProperty p => _copySwitch(p, state: state),
    final LightProperty p => _copyLight(p, state: state),
    final BlobProperty p => _copyBlob(p, state: state),
  };
}

TextProperty _copyText(
  TextProperty p, {
  PropertyState? state,
  double? timeout,
  DateTime? timestamp,
  List<TextElement>? elements,
}) =>
    TextProperty(
      device: p.device,
      name: p.name,
      label: p.label,
      group: p.group,
      state: state ?? p.state,
      permission: p.permission,
      timeout: timeout ?? p.timeout,
      timestamp: timestamp ?? p.timestamp,
      elements: elements ?? p.elements,
    );

NumberProperty _copyNumber(
  NumberProperty p, {
  PropertyState? state,
  double? timeout,
  DateTime? timestamp,
  List<NumberElement>? elements,
}) =>
    NumberProperty(
      device: p.device,
      name: p.name,
      label: p.label,
      group: p.group,
      state: state ?? p.state,
      permission: p.permission,
      timeout: timeout ?? p.timeout,
      timestamp: timestamp ?? p.timestamp,
      elements: elements ?? p.elements,
    );

SwitchProperty _copySwitch(
  SwitchProperty p, {
  PropertyState? state,
  double? timeout,
  DateTime? timestamp,
  List<SwitchElement>? elements,
}) =>
    SwitchProperty(
      device: p.device,
      name: p.name,
      label: p.label,
      group: p.group,
      state: state ?? p.state,
      permission: p.permission,
      timeout: timeout ?? p.timeout,
      timestamp: timestamp ?? p.timestamp,
      rule: p.rule,
      elements: elements ?? p.elements,
    );

LightProperty _copyLight(
  LightProperty p, {
  PropertyState? state,
  DateTime? timestamp,
  List<LightElement>? elements,
}) =>
    LightProperty(
      device: p.device,
      name: p.name,
      label: p.label,
      group: p.group,
      state: state ?? p.state,
      timestamp: timestamp ?? p.timestamp,
      elements: elements ?? p.elements,
    );

BlobProperty _copyBlob(
  BlobProperty p, {
  PropertyState? state,
  double? timeout,
  DateTime? timestamp,
  List<BlobElement>? elements,
}) =>
    BlobProperty(
      device: p.device,
      name: p.name,
      label: p.label,
      group: p.group,
      state: state ?? p.state,
      permission: p.permission,
      timeout: timeout ?? p.timeout,
      timestamp: timestamp ?? p.timestamp,
      elements: elements ?? p.elements,
    );
