import 'dart:async';

import '../client/client_options.dart';
import '../client/connection_state.dart';
import '../client/events.dart';
import '../exceptions.dart';
import '../model/blob.dart';
import '../model/enums.dart';
import '../model/properties.dart';
import 'device_wrapper.dart';
import 'guider.dart';
import 'standard_properties.dart';
import 'values.dart';

/// A camera (CCD or CMOS).
///
/// ```dart
/// final camera = Camera(await client.waitForDevice('CCD Simulator'));
/// await camera.connect();
/// final image = await camera.expose(const Duration(seconds: 5));
/// File('m42${image.format}').writeAsBytesSync(image.decompress());
/// ```
///
/// Images arrive as BLOBs. For applications that download many images,
/// enable `IndiClientOptions.separateBlobConnection` so downloads never
/// delay other commands.
///
/// {@category Device wrappers}
final class Camera extends IndiDeviceWrapper with GuiderControls {
  /// Wraps [device]. [imageProperty] is the BLOB property with the main
  /// sensor's images: `CCD1`, or `CCD2` for a guide head.
  Camera(super.device, {this.imageProperty = StandardProperties.ccd1});

  /// The BLOB property images arrive on.
  final String imageProperty;

  // -------------------------------------------------------------------------
  // Exposures.
  // -------------------------------------------------------------------------

  /// Takes an exposure of [duration] and returns the image.
  ///
  /// Frame type, binning and region are changed first when given. Images
  /// are enabled for this client if needed (BLOB mode `Also`), and an
  /// upload mode of "local only" is changed to "both", so the image always
  /// reaches the client.
  ///
  /// Fails with an [IndiPropertyAlertException] if the camera reports an
  /// error, and with an [IndiTimeoutException] if the image doesn't arrive
  /// within [duration] plus [downloadTimeout].
  Future<IndiBlob> expose(
    Duration duration, {
    FrameType? frameType,
    int? binning,
    SensorFrame? frame,
    Duration downloadTimeout = const Duration(seconds: 60),
  }) async {
    if (frameType != null) await setFrameType(frameType);
    if (binning != null) await setBinning(binning, binning);
    if (frame != null) await setFrame(frame);
    await _ensureImagesReachClient();
    // Listen before exposing, so a fast camera can't win the race.
    final image = nextImage(timeout: duration + downloadTimeout);
    try {
      await device.sendNumber(
        StandardProperties.ccdExposure,
        StandardElements.ccdExposureValue,
        duration.inMicroseconds / Duration.microsecondsPerSecond,
        completion: CommandCompletion.sent,
      );
    } on Object {
      image.ignore();
      rethrow;
    }
    return image;
  }

  /// Waits for the next image to arrive, whoever started the exposure.
  ///
  /// Fails if the exposure goes to `Alert`, the device is removed, the
  /// connection is lost, or [timeout] expires.
  Future<IndiBlob> nextImage({Duration? timeout}) {
    final completer = Completer<IndiBlob>();
    late final StreamSubscription<IndiEvent> subscription;
    Timer? timer;
    void finish(void Function() action) {
      if (completer.isCompleted) return;
      timer?.cancel();
      unawaited(subscription.cancel());
      action();
    }

    subscription = client.events.listen(
      (event) {
        switch (event) {
          case PropertyUpdated(:final device, :final property, :final previous)
              when device.name == name && property.name == imageProperty:
            final blob = _newBlob(property, previous);
            if (blob != null) finish(() => completer.complete(blob));
          case PropertyUpdated(:final device, :final property)
              when device.name == name &&
                  property.name == StandardProperties.ccdExposure &&
                  property.state == PropertyState.alert:
            finish(() => completer.completeError(IndiPropertyAlertException(
                  _lastMessage ?? 'The exposure failed',
                  device: name,
                  property: StandardProperties.ccdExposure,
                )));
          case DeviceRemoved(:final device) when device.name == name:
            finish(() => completer.completeError(
                  IndiNotFoundException('Device "$name" was removed'),
                ));
          case ConnectionStateChanged(:final state)
              when state is! IndiConnected:
            finish(() => completer.completeError(
                  const IndiConnectionLostException(
                    'Connection lost while waiting for an image',
                  ),
                ));
          default:
            break;
        }
      },
      onDone: () => finish(() => completer.completeError(
            const IndiClosedException('The client was closed'),
          )),
    );
    if (timeout != null) {
      timer = Timer(timeout, () {
        finish(() => completer.completeError(IndiTimeoutException(
              'No image from "$name" within $timeout',
              timeout,
            )));
      });
    }
    return completer.future;
  }

  /// Every image that arrives from now on: exposures, including those
  /// started by other clients, and video stream frames.
  Stream<IndiBlob> get images => device
      .eventsOf<PropertyUpdated>()
      .where((event) => event.property.name == imageProperty)
      .map((event) => _newBlob(event.property, event.previous))
      .where((blob) => blob != null)
      .cast<IndiBlob>();

  static IndiBlob? _newBlob(IndiProperty property, IndiProperty previous) {
    if (property is! BlobProperty || previous is! BlobProperty) return null;
    for (final element in property.elements) {
      final blob = element.blob;
      if (blob != null &&
          blob.bytes.isNotEmpty &&
          !identical(blob, previous[element.name]?.blob)) {
        return blob;
      }
    }
    return null;
  }

  String? get _lastMessage {
    final messages = device.messages;
    return messages.isEmpty ? null : messages.last.text;
  }

  Future<void> _ensureImagesReachClient() async {
    final mode = client.blobMode(device: name, property: imageProperty);
    if (mode == BlobMode.never) {
      await device.setBlobMode(BlobMode.also, property: imageProperty);
    }
    if (uploadMode == UploadMode.local) await setUploadMode(UploadMode.both);
  }

  /// Aborts the current exposure.
  Future<void> abortExposure() => device.setSwitch(
        StandardProperties.ccdAbortExposure,
        StandardElements.abort,
      );

  /// Whether an exposure is in progress.
  bool get isExposing =>
      stateOf(StandardProperties.ccdExposure) == PropertyState.busy;

  /// The time left in the current exposure, or `null` when idle.
  Duration? get exposureRemaining {
    if (!isExposing) return null;
    final seconds = numberValue(
      StandardProperties.ccdExposure,
      StandardElements.ccdExposureValue,
    );
    return seconds == null
        ? null
        : Duration(microseconds: (seconds * 1e6).round());
  }

  // -------------------------------------------------------------------------
  // Settings.
  // -------------------------------------------------------------------------

  /// The kind of frame the next exposure takes.
  FrameType? get frameType {
    final active =
        device.getSwitch(StandardProperties.ccdFrameType)?.activeElement?.name;
    for (final type in FrameType.values) {
      if (type.element == active) return type;
    }
    return null;
  }

  /// Sets the kind of frame.
  Future<void> setFrameType(FrameType type) =>
      ensureSwitch(StandardProperties.ccdFrameType, type.element);

  /// The binning as (horizontal, vertical), or `null` if not supported.
  (int, int)? get binning {
    final property = device.getNumber(StandardProperties.ccdBinning);
    final x = property?.valueOf(StandardElements.horizontalBinning);
    final y = property?.valueOf(StandardElements.verticalBinning);
    if (x == null || y == null) return null;
    return (x.round(), y.round());
  }

  /// Sets the binning.
  Future<void> setBinning(int horizontal, [int? vertical]) =>
      device.sendNumbers(StandardProperties.ccdBinning, {
        StandardElements.horizontalBinning: horizontal,
        StandardElements.verticalBinning: vertical ?? horizontal,
      });

  /// The region of the sensor read out.
  SensorFrame? get frame {
    final property = device.getNumber(StandardProperties.ccdFrame);
    final x = property?.valueOf(StandardElements.x);
    final y = property?.valueOf(StandardElements.y);
    final width = property?.valueOf(StandardElements.width);
    final height = property?.valueOf(StandardElements.height);
    if (x == null || y == null || width == null || height == null) {
      return null;
    }
    return SensorFrame(
      x: x.round(),
      y: y.round(),
      width: width.round(),
      height: height.round(),
    );
  }

  /// Sets the region of the sensor to read out.
  Future<void> setFrame(SensorFrame frame) =>
      device.sendNumbers(StandardProperties.ccdFrame, {
        StandardElements.x: frame.x,
        StandardElements.y: frame.y,
        StandardElements.width: frame.width,
        StandardElements.height: frame.height,
      });

  /// Reads out the whole sensor again.
  Future<void> resetFrame() => device.setSwitch(
        StandardProperties.ccdFrameReset,
        StandardElements.reset,
      );

  /// Information about the sensor.
  SensorInfo? get sensorInfo {
    final info = device.getNumber(StandardProperties.ccdInfo);
    if (info == null) return null;
    final pixel = info.valueOf(StandardElements.ccdPixelSize) ?? 0;
    return SensorInfo(
      width: info.valueOf(StandardElements.ccdMaxX)?.round() ?? 0,
      height: info.valueOf(StandardElements.ccdMaxY)?.round() ?? 0,
      pixelSizeX: info.valueOf(StandardElements.ccdPixelSizeX) ?? pixel,
      pixelSizeY: info.valueOf(StandardElements.ccdPixelSizeY) ?? pixel,
      bitsPerPixel:
          info.valueOf(StandardElements.ccdBitsPerPixel)?.round() ?? 0,
    );
  }

  /// The sensor temperature in °C, if the camera reports it.
  double? get temperature => numberValue(
        StandardProperties.ccdTemperature,
        StandardElements.ccdTemperatureValue,
      );

  /// The sensor temperature, now and after every change.
  Stream<double> get temperatureStream => watchValue<NumberProperty, double>(
        StandardProperties.ccdTemperature,
        (p) => p.valueOf(StandardElements.ccdTemperatureValue),
      );

  /// Sets the target sensor temperature in °C.
  ///
  /// By default completes once the request is sent; cooling can take many
  /// minutes. With [waitUntilReached] it completes when the camera reports
  /// the temperature was reached.
  Future<void> setTemperature(
    double celsius, {
    bool waitUntilReached = false,
    Duration? timeout,
  }) =>
      device.sendNumber(
        StandardProperties.ccdTemperature,
        StandardElements.ccdTemperatureValue,
        celsius,
        completion: waitUntilReached
            ? CommandCompletion.afterBusy
            : CommandCompletion.sent,
        timeout: timeout,
      );

  /// Whether the cooler is on, or `null` if the camera has none.
  bool? get isCoolerOn =>
      switchValue(StandardProperties.ccdCooler, StandardElements.coolerOn);

  /// Turns the cooler on or off.
  Future<void> setCooler(bool on) => device.setSwitch(
        StandardProperties.ccdCooler,
        on ? StandardElements.coolerOn : StandardElements.coolerOff,
      );

  /// The cooler power in percent, if reported.
  double? get coolerPower => numberValue(
        StandardProperties.ccdCoolerPower,
        StandardElements.ccdCoolerValue,
      );

  /// The gain, from `CCD_GAIN` or from the `Gain` control of drivers such
  /// as ZWO's.
  double? get gain => _control(
        StandardProperties.ccdGain,
        StandardElements.gain,
        'gain',
      )?.value;

  /// Sets the gain. See [gain].
  Future<void> setGain(double value) => _setControl(
      StandardProperties.ccdGain, StandardElements.gain, 'gain', value);

  /// The offset, from `CCD_OFFSET` or from the `Offset` control.
  double? get offset => _control(
        StandardProperties.ccdOffset,
        StandardElements.offsetValue,
        'offset',
      )?.value;

  /// Sets the offset. See [offset].
  Future<void> setOffset(double value) => _setControl(
        StandardProperties.ccdOffset,
        StandardElements.offsetValue,
        'offset',
        value,
      );

  NumberElement? _control(String property, String element, String control) {
    final dedicated = device.getNumber(property)?[element];
    if (dedicated != null) return dedicated;
    final controls = device.getNumber(StandardProperties.ccdControls);
    return controls?.elements
        .where((e) => e.name.toLowerCase() == control)
        .firstOrNull;
  }

  Future<void> _setControl(
    String property,
    String element,
    String control,
    double value,
  ) {
    if (device.getNumber(property)?[element] != null) {
      return device.sendNumber(property, element, value);
    }
    final controlElement = _control(property, element, control);
    if (controlElement == null) {
      throw IndiNotFoundException('Camera "$name" has no $control setting');
    }
    return device.sendNumber(
      StandardProperties.ccdControls,
      controlElement.name,
      value,
    );
  }

  /// The image format.
  TransferFormat? get transferFormat {
    final active = device
        .getSwitch(StandardProperties.ccdTransferFormat)
        ?.activeElement
        ?.name;
    for (final format in TransferFormat.values) {
      if (format.element == active) return format;
    }
    return null;
  }

  /// Sets the image format.
  Future<void> setTransferFormat(TransferFormat format) =>
      ensureSwitch(StandardProperties.ccdTransferFormat, format.element);

  /// Whether images are compressed before sending.
  bool? get isCompressed => switchValue(
        StandardProperties.ccdCompression,
        StandardElements.indiEnabled,
      );

  /// Turns image compression on or off. Compressed images (format ending
  /// in `.z`) are smaller on the network; decompress them with
  /// [IndiBlob.decompress].
  Future<void> setCompression(bool enabled) => device.setSwitch(
        StandardProperties.ccdCompression,
        enabled ? StandardElements.indiEnabled : StandardElements.indiDisabled,
      );

  /// Where images go.
  UploadMode? get uploadMode {
    final active =
        device.getSwitch(StandardProperties.uploadMode)?.activeElement?.name;
    for (final mode in UploadMode.values) {
      if (mode.element == active) return mode;
    }
    return null;
  }

  /// Sets where images go.
  Future<void> setUploadMode(UploadMode mode) =>
      ensureSwitch(StandardProperties.uploadMode, mode.element);

  /// Starts video streaming; frames arrive on [images].
  Future<void> startStreaming() async {
    await _ensureImagesReachClient();
    await device.setSwitch(
      StandardProperties.ccdVideoStream,
      StandardElements.streamOn,
    );
  }

  /// Stops video streaming.
  Future<void> stopStreaming() => device.setSwitch(
        StandardProperties.ccdVideoStream,
        StandardElements.streamOff,
      );
}
