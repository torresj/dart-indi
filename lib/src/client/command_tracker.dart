import 'dart:async';

import '../exceptions.dart';
import '../model/enums.dart';
import '../model/properties.dart';
import 'client_options.dart';

/// Tracks commands waiting for the driver's answer and completes them when
/// the property leaves the `Busy` state. Internal to the client.
final class CommandTracker {
  final Map<(String, String), List<_Pending>> _pending = {};

  /// Waits for the answer to a command sent to [property] of [device].
  ///
  /// [matches] tells whether an update reports exactly the requested
  /// values, for [CommandCompletion.afterBusy].
  Future<IndiProperty> track({
    required String device,
    required String property,
    required CommandCompletion completion,
    required bool Function(IndiProperty update) matches,
    Duration? timeout,
  }) {
    final key = (device, property);
    final pending = _Pending(completion, matches);
    _pending.putIfAbsent(key, () => []).add(pending);
    if (timeout != null) {
      pending.timer = Timer(timeout, () {
        _remove(key, pending);
        pending.fail(IndiTimeoutException(
          'No answer for "$device.$property" within $timeout',
          timeout,
        ));
      });
    }
    return pending.completer.future;
  }

  /// Reports an update of a property received from the server.
  void onUpdate(IndiProperty property, {String? message}) {
    final key = (property.device, property.name);
    final list = _pending[key];
    if (list == null) return;
    for (final pending in List.of(list)) {
      switch (property.state) {
        case PropertyState.alert:
          _remove(key, pending);
          pending.fail(IndiPropertyAlertException(
            message == null || message.isEmpty
                ? '"${property.device}.${property.name}" went to Alert'
                : message,
            device: property.device,
            property: property.name,
          ));
        case PropertyState.busy:
          pending.sawBusy = true;
        case PropertyState.ok || PropertyState.idle:
          if (pending.completion == CommandCompletion.nextUpdate ||
              pending.sawBusy ||
              pending.matches(property)) {
            _remove(key, pending);
            pending.complete(property);
          }
      }
    }
  }

  /// Fails the commands waiting on [property] of [device], or on every
  /// property of [device] when [property] is `null`.
  void onRemoved(String device, [String? property]) {
    for (final key in _pending.keys.toList()) {
      if (key.$1 != device || (property != null && key.$2 != property)) {
        continue;
      }
      for (final pending in _pending.remove(key)!) {
        pending.fail(IndiPropertyRemovedException(
          '"${key.$1}.${key.$2}" was removed while a command was pending',
        ));
      }
    }
  }

  /// Fails every pending command with [error].
  void failAll(Object error) {
    final all = _pending.values.expand((list) => list).toList();
    _pending.clear();
    for (final pending in all) {
      pending.fail(error);
    }
  }

  void _remove((String, String) key, _Pending pending) {
    final list = _pending[key];
    if (list == null) return;
    list.remove(pending);
    if (list.isEmpty) _pending.remove(key);
  }
}

final class _Pending {
  _Pending(this.completion, this.matches);

  final CommandCompletion completion;
  final bool Function(IndiProperty) matches;
  final Completer<IndiProperty> completer = Completer<IndiProperty>();
  Timer? timer;
  bool sawBusy = false;

  void complete(IndiProperty property) {
    timer?.cancel();
    if (!completer.isCompleted) completer.complete(property);
  }

  void fail(Object error) {
    timer?.cancel();
    if (!completer.isCompleted) completer.completeError(error);
  }
}
