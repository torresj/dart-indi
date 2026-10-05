import 'dart:async';

import 'package:meta/meta.dart';

import '../client/client_options.dart';
import '../client/indi_client.dart';
import '../model/enums.dart';
import '../model/properties.dart';
import 'standard_properties.dart';

/// The base of the typed device wrappers, such as `Telescope` and
/// `Camera`.
///
/// A wrapper adds methods with meaningful names and types on top of an
/// [IndiDevice], using the standard INDI properties. It holds no state of
/// its own, so it is cheap to create and always reflects the device. The
/// generic API stays available through [device] for anything driver
/// specific.
///
/// {@category Device wrappers}
abstract base class IndiDeviceWrapper {
  /// Wraps [device].
  IndiDeviceWrapper(this.device);

  /// The wrapped device.
  final IndiDevice device;

  /// The device name.
  String get name => device.name;

  /// The client the device belongs to.
  IndiClient get client => device.client;

  /// Whether the device can be used now. See [IndiDevice.isAvailable].
  bool get isAvailable => device.isAvailable;

  /// Whether the driver is connected to its hardware.
  bool get isConnected => device.isConnected;

  /// Information about the driver.
  DriverInfo? get driverInfo => device.driverInfo;

  /// Connects the driver to its hardware. See [IndiDevice.connect].
  Future<void> connect({Duration? timeout}) => device.connect(timeout: timeout);

  /// Disconnects the driver from its hardware.
  Future<void> disconnect({Duration? timeout}) =>
      device.disconnect(timeout: timeout);

  /// Sets the serial or network port the driver uses, such as
  /// `/dev/ttyUSB0`.
  Future<void> setPort(String port) => device.sendText(
        StandardProperties.devicePort,
        StandardElements.port,
        port,
      );

  /// Saves the current settings as the driver's configuration.
  Future<void> saveConfig() => device.setSwitch(
        StandardProperties.configProcess,
        StandardElements.configSave,
      );

  /// Loads the driver's saved configuration.
  Future<void> loadConfig() => device.setSwitch(
        StandardProperties.configProcess,
        StandardElements.configLoad,
      );

  /// Sets how often the driver polls the hardware.
  Future<void> setPollingPeriod(Duration period) => device.sendNumber(
        StandardProperties.pollingPeriod,
        StandardElements.periodMs,
        period.inMilliseconds,
      );

  /// Turns the driver's debug logging on or off.
  Future<void> setDebug(bool enabled) => device.setSwitch(
        StandardProperties.debug,
        enabled ? StandardElements.enable : StandardElements.disable,
      );

  /// Turns the driver's simulation mode on or off.
  Future<void> setSimulation(bool enabled) => device.setSwitch(
        StandardProperties.simulation,
        enabled ? StandardElements.enable : StandardElements.disable,
      );

  /// The value of [element] of the number property [property], or `null`.
  @protected
  double? numberValue(String property, String element) =>
      device.getNumber(property)?.valueOf(element);

  /// The text of [element] of the text property [property], or `null`.
  @protected
  String? textValue(String property, String element) =>
      device.getText(property)?.valueOf(element);

  /// Whether [element] of the switch property [property] is on, or `null`
  /// if the property does not exist.
  @protected
  bool? switchValue(String property, String element) =>
      device.getSwitch(property)?.isOn(element);

  /// The state of [property], or `null` if it does not exist.
  @protected
  PropertyState? stateOf(String property) => device[property]?.state;

  /// A stream of values derived from [property]: the current value first,
  /// then each change. Snapshots that map to `null` are skipped, and so
  /// are repeated values.
  @protected
  Stream<T> watchValue<P extends IndiProperty, T extends Object>(
    String property,
    T? Function(P property) map,
  ) {
    return Stream<T>.multi((controller) {
      T? last;
      final subscription = device.watch<P>(property).listen(
        (snapshot) {
          final value = map(snapshot);
          if (value == null || value == last) return;
          last = value;
          controller.add(value);
        },
        onError: controller.addError,
        onDone: controller.close,
      );
      controller
        ..onCancel = subscription.cancel
        ..onPause = subscription.pause
        ..onResume = subscription.resume;
    });
  }

  /// Turns on [element] of the switch property [property], unless it is
  /// already on.
  @protected
  Future<void> ensureSwitch(String property, String element) async {
    if (switchValue(property, element) ?? false) return;
    await device.setSwitch(property, element);
  }

  /// Sends numbers and waits for the driver to finish, for motions that go
  /// `Busy` while in progress.
  @protected
  Future<NumberProperty> moveNumbers(
    String property,
    Map<String, num> values, {
    Duration? timeout,
  }) =>
      device.sendNumbers(
        property,
        values,
        completion: CommandCompletion.afterBusy,
        timeout: timeout,
      );

  @override
  String toString() => '$runtimeType($name)';
}
