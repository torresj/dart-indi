/// The kinds of device a driver implements, reported in the
/// `DRIVER_INTERFACE` element of the `DRIVER_INFO` property as a bit mask.
///
/// A driver can implement several interfaces; a camera with a built-in
/// guide port, for example, is both [ccd] and [guider].
///
/// {@category Model}
enum DeviceInterface {
  /// A telescope mount.
  telescope(1 << 0),

  /// A camera (CCD or CMOS).
  ccd(1 << 1),

  /// A device that accepts guiding pulses (ST4).
  guider(1 << 2),

  /// A focuser.
  focuser(1 << 3),

  /// A filter wheel.
  filterWheel(1 << 4),

  /// An observatory dome or roll-off roof.
  dome(1 << 5),

  /// A GPS receiver.
  gps(1 << 6),

  /// A weather station.
  weather(1 << 7),

  /// An adaptive optics unit.
  adaptiveOptics(1 << 8),

  /// A dust cap.
  dustCap(1 << 9),

  /// A light box or flat panel.
  lightBox(1 << 10),

  /// A detector, such as a photometer.
  detector(1 << 11),

  /// A field rotator.
  rotator(1 << 12),

  /// A spectrograph.
  spectrograph(1 << 13),

  /// A correlator (radio astronomy).
  correlator(1 << 14),

  /// An auxiliary device.
  auxiliary(1 << 15),

  /// A device with digital outputs.
  output(1 << 16),

  /// A device with digital inputs.
  input(1 << 17),

  /// A power distribution box.
  power(1 << 18),

  /// An inertial measurement unit.
  imu(1 << 19),

  /// A polar alignment correction device.
  polarAlignmentCorrection(1 << 20);

  const DeviceInterface(this.mask);

  /// The bit for this interface in the `DRIVER_INTERFACE` mask.
  final int mask;

  /// The interfaces whose bits are set in [mask].
  static Set<DeviceInterface> fromMask(int mask) => {
        for (final value in values)
          if (mask & value.mask != 0) value
      };

  /// The mask with the bits of all [interfaces] set.
  static int toMask(Iterable<DeviceInterface> interfaces) =>
      interfaces.fold(0, (mask, value) => mask | value.mask);
}
