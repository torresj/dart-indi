// The names below come from the INDI standard properties:
// https://indilib.org/develop/developer-manual/101-standard-properties.html

/// Names of the standard INDI properties.
///
/// Drivers that follow the standard use these names, which lets clients
/// work with any device of a kind. Use them with the generic API:
///
/// ```dart
/// final coords = mount.getNumber(StandardProperties.equatorialEodCoord);
/// final ra = coords?.valueOf(StandardElements.ra);
/// ```
///
/// {@category Device wrappers}
abstract final class StandardProperties {
  // General.

  /// Connects the driver to its hardware (switch: CONNECT, DISCONNECT).
  static const connection = 'CONNECTION';

  /// The serial or network port (text: PORT).
  static const devicePort = 'DEVICE_PORT';

  /// Driver name, executable, version and interfaces (text).
  static const driverInfo = 'DRIVER_INFO';

  /// Driver debug logging (switch: ENABLE, DISABLE).
  static const debug = 'DEBUG';

  /// Driver simulation mode (switch: ENABLE, DISABLE).
  static const simulation = 'SIMULATION';

  /// Saves or loads the driver configuration (switch: CONFIG_LOAD,
  /// CONFIG_SAVE, CONFIG_DEFAULT, CONFIG_PURGE).
  static const configProcess = 'CONFIG_PROCESS';

  /// How often the driver polls the hardware (number: PERIOD_MS).
  static const pollingPeriod = 'POLLING_PERIOD';

  /// The UTC time and the UTC offset (text: UTC, OFFSET).
  static const timeUtc = 'TIME_UTC';

  /// The observing site (number: LAT, LONG, ELEV).
  static const geographicCoord = 'GEOGRAPHIC_COORD';

  /// The devices a driver snoops on (text: ACTIVE_TELESCOPE, ACTIVE_CCD,
  /// …).
  static const activeDevices = 'ACTIVE_DEVICES';

  /// Where images go (switch: UPLOAD_CLIENT, UPLOAD_LOCAL, UPLOAD_BOTH).
  static const uploadMode = 'UPLOAD_MODE';

  /// Where local uploads are saved (text: UPLOAD_DIR, UPLOAD_PREFIX).
  static const uploadSettings = 'UPLOAD_SETTINGS';

  // Telescope.

  /// Current coordinates, epoch of date (number: RA in hours, DEC in
  /// degrees). Writing them slews, tracks or syncs per [onCoordSet].
  static const equatorialEodCoord = 'EQUATORIAL_EOD_COORD';

  /// Current coordinates, J2000 (number: RA, DEC).
  static const equatorialCoord = 'EQUATORIAL_COORD';

  /// The target of the last slew (number: RA, DEC).
  static const targetEodCoord = 'TARGET_EOD_COORD';

  /// Horizontal coordinates (number: ALT, AZ in degrees).
  static const horizontalCoord = 'HORIZONTAL_COORD';

  /// What writing coordinates does (switch: SLEW, TRACK, SYNC).
  static const onCoordSet = 'ON_COORD_SET';

  /// Stops all motion (switch: ABORT).
  static const telescopeAbortMotion = 'TELESCOPE_ABORT_MOTION';

  /// Parks or unparks the mount (switch: PARK, UNPARK).
  static const telescopePark = 'TELESCOPE_PARK';

  /// Tracking on or off (switch: TRACK_ON, TRACK_OFF).
  static const telescopeTrackState = 'TELESCOPE_TRACK_STATE';

  /// The tracking rate (switch: TRACK_SIDEREAL, TRACK_SOLAR, TRACK_LUNAR,
  /// TRACK_CUSTOM).
  static const telescopeTrackMode = 'TELESCOPE_TRACK_MODE';

  /// The rate of manual motion (switch, names depend on the driver).
  static const telescopeSlewRate = 'TELESCOPE_SLEW_RATE';

  /// Manual motion in declination (switch: MOTION_NORTH, MOTION_SOUTH).
  static const telescopeMotionNs = 'TELESCOPE_MOTION_NS';

  /// Manual motion in right ascension (switch: MOTION_WEST, MOTION_EAST).
  static const telescopeMotionWe = 'TELESCOPE_MOTION_WE';

  /// The side of the pier (switch: PIER_WEST, PIER_EAST).
  static const telescopePierSide = 'TELESCOPE_PIER_SIDE';

  /// Optical information (number: TELESCOPE_APERTURE,
  /// TELESCOPE_FOCAL_LENGTH, GUIDER_APERTURE, GUIDER_FOCAL_LENGTH, in mm).
  static const telescopeInfo = 'TELESCOPE_INFO';

  /// Timed guide pulses in declination (number: TIMED_GUIDE_N,
  /// TIMED_GUIDE_S, in ms).
  static const telescopeTimedGuideNs = 'TELESCOPE_TIMED_GUIDE_NS';

  /// Timed guide pulses in right ascension (number: TIMED_GUIDE_W,
  /// TIMED_GUIDE_E, in ms).
  static const telescopeTimedGuideWe = 'TELESCOPE_TIMED_GUIDE_WE';

  // Camera.

  /// Starts an exposure (number: CCD_EXPOSURE_VALUE, in seconds).
  static const ccdExposure = 'CCD_EXPOSURE';

  /// Aborts the exposure (switch: ABORT).
  static const ccdAbortExposure = 'CCD_ABORT_EXPOSURE';

  /// The region of interest (number: X, Y, WIDTH, HEIGHT).
  static const ccdFrame = 'CCD_FRAME';

  /// Resets the region of interest (switch: RESET).
  static const ccdFrameReset = 'CCD_FRAME_RESET';

  /// Binning (number: HOR_BIN, VER_BIN).
  static const ccdBinning = 'CCD_BINNING';

  /// The kind of frame (switch: FRAME_LIGHT, FRAME_BIAS, FRAME_DARK,
  /// FRAME_FLAT).
  static const ccdFrameType = 'CCD_FRAME_TYPE';

  /// The sensor temperature (number: CCD_TEMPERATURE_VALUE, in °C).
  static const ccdTemperature = 'CCD_TEMPERATURE';

  /// The cooler (switch: COOLER_ON, COOLER_OFF).
  static const ccdCooler = 'CCD_COOLER';

  /// The cooler power (number: CCD_COOLER_VALUE, in %).
  static const ccdCoolerPower = 'CCD_COOLER_POWER';

  /// Sensor information (number: CCD_MAX_X, CCD_MAX_Y, CCD_PIXEL_SIZE,
  /// CCD_PIXEL_SIZE_X, CCD_PIXEL_SIZE_Y, CCD_BITSPERPIXEL).
  static const ccdInfo = 'CCD_INFO';

  /// Image compression (switch: INDI_ENABLED, INDI_DISABLED).
  static const ccdCompression = 'CCD_COMPRESSION';

  /// Image format (switch: FORMAT_FITS, FORMAT_NATIVE, FORMAT_XISF).
  static const ccdTransferFormat = 'CCD_TRANSFER_FORMAT';

  /// Gain, on drivers with a dedicated property (number: GAIN).
  static const ccdGain = 'CCD_GAIN';

  /// Offset, on drivers with a dedicated property (number: OFFSET).
  static const ccdOffset = 'CCD_OFFSET';

  /// Camera controls such as Gain and Offset, on drivers like ZWO.
  static const ccdControls = 'CCD_CONTROLS';

  /// Video streaming (switch: STREAM_ON, STREAM_OFF).
  static const ccdVideoStream = 'CCD_VIDEO_STREAM';

  /// The image of the main sensor (BLOB: CCD1).
  static const ccd1 = 'CCD1';

  /// The image of the guide head (BLOB: CCD2).
  static const ccd2 = 'CCD2';

  // Focuser.

  /// The direction of relative moves (switch: FOCUS_INWARD, FOCUS_OUTWARD).
  static const focusMotion = 'FOCUS_MOTION';

  /// Relative move (number: FOCUS_RELATIVE_POSITION, in steps).
  static const relFocusPosition = 'REL_FOCUS_POSITION';

  /// Absolute position (number: FOCUS_ABSOLUTE_POSITION, in steps).
  static const absFocusPosition = 'ABS_FOCUS_POSITION';

  /// Stops the focuser (switch: ABORT).
  static const focusAbortMotion = 'FOCUS_ABORT_MOTION';

  /// Redefines the current position (number: FOCUS_SYNC_VALUE).
  static const focusSync = 'FOCUS_SYNC';

  /// The maximum position (number: FOCUS_MAX_VALUE).
  static const focusMax = 'FOCUS_MAX';

  /// The speed (number: FOCUS_SPEED_VALUE).
  static const focusSpeed = 'FOCUS_SPEED';

  /// The focuser temperature (number: TEMPERATURE, in °C).
  static const focusTemperature = 'FOCUS_TEMPERATURE';

  /// Reverses the direction (switch: INDI_ENABLED, INDI_DISABLED).
  static const focusReverseMotion = 'FOCUS_REVERSE_MOTION';

  // Filter wheel.

  /// The current slot, from 1 (number: FILTER_SLOT_VALUE).
  static const filterSlot = 'FILTER_SLOT';

  /// The filter names (text: FILTER_SLOT_NAME_1, FILTER_SLOT_NAME_2, …).
  static const filterName = 'FILTER_NAME';

  // Dome.

  /// The shutter (switch: SHUTTER_OPEN, SHUTTER_CLOSE).
  static const domeShutter = 'DOME_SHUTTER';

  /// Manual rotation (switch: DOME_CW, DOME_CCW).
  static const domeMotion = 'DOME_MOTION';

  /// The azimuth (number: DOME_ABSOLUTE_POSITION, in degrees).
  static const absDomePosition = 'ABS_DOME_POSITION';

  /// Relative rotation (number: DOME_RELATIVE_POSITION, in degrees).
  static const relDomePosition = 'REL_DOME_POSITION';

  /// Stops the dome (switch: ABORT).
  static const domeAbortMotion = 'DOME_ABORT_MOTION';

  /// Parks or unparks the dome (switch: PARK, UNPARK).
  static const domePark = 'DOME_PARK';

  /// Slaving to the mount (switch: DOME_AUTOSYNC_ENABLE,
  /// DOME_AUTOSYNC_DISABLE).
  static const domeAutosync = 'DOME_AUTOSYNC';

  // Rotator.

  /// The angle (number: ANGLE, in degrees).
  static const absRotatorAngle = 'ABS_ROTATOR_ANGLE';

  /// Stops the rotator (switch: ABORT).
  static const rotatorAbortMotion = 'ROTATOR_ABORT_MOTION';

  /// Redefines the current angle (number: ANGLE).
  static const syncRotatorAngle = 'SYNC_ROTATOR_ANGLE';

  /// Reverses the direction (switch: INDI_ENABLED, INDI_DISABLED).
  static const rotatorReverse = 'ROTATOR_REVERSE';

  // Weather.

  /// Safety status per parameter (light).
  static const weatherStatus = 'WEATHER_STATUS';

  /// Current readings (number, names depend on the driver).
  static const weatherParameters = 'WEATHER_PARAMETERS';

  /// Refreshes the readings (switch: REFRESH).
  static const weatherRefresh = 'WEATHER_REFRESH';

  // GPS.

  /// Refreshes the position and time (switch: REFRESH).
  static const gpsRefresh = 'GPS_REFRESH';

  // Dust cap and light box.

  /// Closes (parks) or opens (unparks) the cap (switch: PARK, UNPARK).
  static const capPark = 'CAP_PARK';

  /// Stops the cap (switch: ABORT). Only drivers that can abort define it.
  static const capAbort = 'CAP_ABORT';

  /// The light (switch: FLAT_LIGHT_ON, FLAT_LIGHT_OFF).
  static const flatLightControl = 'FLAT_LIGHT_CONTROL';

  /// The brightness (number: FLAT_LIGHT_INTENSITY_VALUE).
  static const flatLightIntensity = 'FLAT_LIGHT_INTENSITY';

  // Inputs and outputs.

  /// The prefix of the digital inputs, followed by the input number from
  /// 1 (switch: OFF, ON; read only).
  static const digitalInputPrefix = 'DIGITAL_INPUT_';

  /// The prefix of the digital outputs, followed by the output number
  /// from 1 (switch: OFF, ON).
  static const digitalOutputPrefix = 'DIGITAL_OUTPUT_';

  /// The prefix of the analog inputs, followed by the input number from 1
  /// (number with one element; read only).
  static const analogInputPrefix = 'ANALOG_INPUT_';

  /// The prefix of the pulse durations, followed by the output number
  /// **from 0** (number: DURATION, in milliseconds).
  static const pulsePrefix = 'PULSE_';

  /// The names of the digital inputs (text: DIGITAL_INPUT_1, …).
  static const digitalInputLabels = 'DIGITAL_INPUT_LABELS';

  /// The names of the digital outputs (text: DIGITAL_OUTPUT_1, …).
  static const digitalOutputLabels = 'DIGITAL_OUTPUT_LABELS';

  /// The names of the analog inputs (text: ANALOG_INPUT_1, …).
  static const analogInputLabels = 'ANALOG_INPUT_LABELS';

  // Sky quality meter.

  /// The readings (number: SKY_BRIGHTNESS, SENSOR_FREQUENCY,
  /// SENSOR_COUNTS, SENSOR_PERIOD, SKY_TEMPERATURE).
  static const skyQuality = 'SKY_QUALITY';

  // Polar alignment correction.

  /// Moves each axis by an angle (number: MANUAL_AZ_STEP,
  /// MANUAL_ALT_STEP, in degrees; write only).
  static const pacManualAdjustment = 'PAC_MANUAL_ADJUSTMENT';

  /// Stops the motion (switch: ABORT).
  static const pacAbortMotion = 'PAC_ABORT_MOTION';

  /// The motor speed (number: PAC_SPEED_VALUE).
  static const pacSpeed = 'PAC_SPEED';

  /// Reverses the azimuth axis (switch: INDI_ENABLED, INDI_DISABLED).
  static const pacAzReverse = 'PAC_AZ_REVERSE';

  /// Reverses the altitude axis (switch: INDI_ENABLED, INDI_DISABLED).
  static const pacAltReverse = 'PAC_ALT_REVERSE';

  /// The position of each axis, if the device knows it (number:
  /// POSITION_AZ, POSITION_ALT, in degrees).
  static const pacPosition = 'PAC_POSITION';
}

/// Names of the elements of the standard INDI properties. See
/// [StandardProperties].
///
/// {@category Device wrappers}
abstract final class StandardElements {
  // General.

  /// CONNECTION: connect.
  static const connect = 'CONNECT';

  /// CONNECTION: disconnect.
  static const disconnect = 'DISCONNECT';

  /// DEVICE_PORT: the port.
  static const port = 'PORT';

  /// DEBUG, SIMULATION: on.
  static const enable = 'ENABLE';

  /// DEBUG, SIMULATION: off.
  static const disable = 'DISABLE';

  /// CONFIG_PROCESS: load the saved configuration.
  static const configLoad = 'CONFIG_LOAD';

  /// CONFIG_PROCESS: save the configuration.
  static const configSave = 'CONFIG_SAVE';

  /// CONFIG_PROCESS: restore the default configuration.
  static const configDefault = 'CONFIG_DEFAULT';

  /// CONFIG_PROCESS: delete the saved configuration.
  static const configPurge = 'CONFIG_PURGE';

  /// POLLING_PERIOD: the period in milliseconds.
  static const periodMs = 'PERIOD_MS';

  /// TIME_UTC: the UTC time, ISO 8601.
  static const utc = 'UTC';

  /// TIME_UTC: the offset from UTC in hours.
  static const offset = 'OFFSET';

  /// GEOGRAPHIC_COORD: latitude in degrees, north positive.
  static const latitude = 'LAT';

  /// GEOGRAPHIC_COORD: longitude in degrees east, 0 to 360.
  static const longitude = 'LONG';

  /// GEOGRAPHIC_COORD: elevation in meters.
  static const elevation = 'ELEV';

  /// UPLOAD_MODE: send images to the client.
  static const uploadClient = 'UPLOAD_CLIENT';

  /// UPLOAD_MODE: save images on the server.
  static const uploadLocal = 'UPLOAD_LOCAL';

  /// UPLOAD_MODE: both.
  static const uploadBoth = 'UPLOAD_BOTH';

  /// Switches named INDI_ENABLED in toggles such as CCD_COMPRESSION.
  static const indiEnabled = 'INDI_ENABLED';

  /// Switches named INDI_DISABLED in toggles such as CCD_COMPRESSION.
  static const indiDisabled = 'INDI_DISABLED';

  /// The single switch of abort properties.
  static const abort = 'ABORT';

  /// PARK properties: park.
  static const park = 'PARK';

  /// PARK properties: unpark.
  static const unpark = 'UNPARK';

  // Telescope.

  /// Right ascension, in hours.
  static const ra = 'RA';

  /// Declination, in degrees.
  static const dec = 'DEC';

  /// Altitude, in degrees.
  static const alt = 'ALT';

  /// Azimuth, in degrees.
  static const az = 'AZ';

  /// ON_COORD_SET: slew and stop.
  static const slew = 'SLEW';

  /// ON_COORD_SET: slew and track.
  static const track = 'TRACK';

  /// ON_COORD_SET: sync.
  static const sync = 'SYNC';

  /// TELESCOPE_TRACK_STATE: tracking on.
  static const trackOn = 'TRACK_ON';

  /// TELESCOPE_TRACK_STATE: tracking off.
  static const trackOff = 'TRACK_OFF';

  /// TELESCOPE_MOTION_NS: north.
  static const motionNorth = 'MOTION_NORTH';

  /// TELESCOPE_MOTION_NS: south.
  static const motionSouth = 'MOTION_SOUTH';

  /// TELESCOPE_MOTION_WE: west.
  static const motionWest = 'MOTION_WEST';

  /// TELESCOPE_MOTION_WE: east.
  static const motionEast = 'MOTION_EAST';

  /// TELESCOPE_PIER_SIDE: west.
  static const pierWest = 'PIER_WEST';

  /// TELESCOPE_PIER_SIDE: east.
  static const pierEast = 'PIER_EAST';

  /// TELESCOPE_INFO: aperture in mm.
  static const telescopeAperture = 'TELESCOPE_APERTURE';

  /// TELESCOPE_INFO: focal length in mm.
  static const telescopeFocalLength = 'TELESCOPE_FOCAL_LENGTH';

  /// TELESCOPE_INFO: guide scope aperture in mm.
  static const guiderAperture = 'GUIDER_APERTURE';

  /// TELESCOPE_INFO: guide scope focal length in mm.
  static const guiderFocalLength = 'GUIDER_FOCAL_LENGTH';

  /// TELESCOPE_TIMED_GUIDE_NS: north pulse in ms.
  static const timedGuideNorth = 'TIMED_GUIDE_N';

  /// TELESCOPE_TIMED_GUIDE_NS: south pulse in ms.
  static const timedGuideSouth = 'TIMED_GUIDE_S';

  /// TELESCOPE_TIMED_GUIDE_WE: west pulse in ms.
  static const timedGuideWest = 'TIMED_GUIDE_W';

  /// TELESCOPE_TIMED_GUIDE_WE: east pulse in ms.
  static const timedGuideEast = 'TIMED_GUIDE_E';

  // Camera.

  /// CCD_EXPOSURE: the duration in seconds.
  static const ccdExposureValue = 'CCD_EXPOSURE_VALUE';

  /// CCD_FRAME: left edge.
  static const x = 'X';

  /// CCD_FRAME: top edge.
  static const y = 'Y';

  /// CCD_FRAME: width.
  static const width = 'WIDTH';

  /// CCD_FRAME: height.
  static const height = 'HEIGHT';

  /// CCD_FRAME_RESET: reset.
  static const reset = 'RESET';

  /// CCD_BINNING: horizontal binning.
  static const horizontalBinning = 'HOR_BIN';

  /// CCD_BINNING: vertical binning.
  static const verticalBinning = 'VER_BIN';

  /// CCD_TEMPERATURE: temperature in °C.
  static const ccdTemperatureValue = 'CCD_TEMPERATURE_VALUE';

  /// CCD_COOLER: on.
  static const coolerOn = 'COOLER_ON';

  /// CCD_COOLER: off.
  static const coolerOff = 'COOLER_OFF';

  /// CCD_COOLER_POWER: power in %.
  static const ccdCoolerValue = 'CCD_COOLER_VALUE';

  /// CCD_INFO: width in pixels.
  static const ccdMaxX = 'CCD_MAX_X';

  /// CCD_INFO: height in pixels.
  static const ccdMaxY = 'CCD_MAX_Y';

  /// CCD_INFO: pixel size in µm.
  static const ccdPixelSize = 'CCD_PIXEL_SIZE';

  /// CCD_INFO: pixel width in µm.
  static const ccdPixelSizeX = 'CCD_PIXEL_SIZE_X';

  /// CCD_INFO: pixel height in µm.
  static const ccdPixelSizeY = 'CCD_PIXEL_SIZE_Y';

  /// CCD_INFO: bits per pixel.
  static const ccdBitsPerPixel = 'CCD_BITSPERPIXEL';

  /// CCD_GAIN: gain.
  static const gain = 'GAIN';

  /// CCD_OFFSET: offset.
  static const offsetValue = 'OFFSET';

  /// CCD_VIDEO_STREAM: on.
  static const streamOn = 'STREAM_ON';

  /// CCD_VIDEO_STREAM: off.
  static const streamOff = 'STREAM_OFF';

  // Focuser.

  /// FOCUS_MOTION: inward.
  static const focusInward = 'FOCUS_INWARD';

  /// FOCUS_MOTION: outward.
  static const focusOutward = 'FOCUS_OUTWARD';

  /// REL_FOCUS_POSITION: steps.
  static const focusRelativePosition = 'FOCUS_RELATIVE_POSITION';

  /// ABS_FOCUS_POSITION: position.
  static const focusAbsolutePosition = 'FOCUS_ABSOLUTE_POSITION';

  /// FOCUS_SYNC: position.
  static const focusSyncValue = 'FOCUS_SYNC_VALUE';

  /// FOCUS_MAX: maximum position.
  static const focusMaxValue = 'FOCUS_MAX_VALUE';

  /// FOCUS_SPEED: speed.
  static const focusSpeedValue = 'FOCUS_SPEED_VALUE';

  /// FOCUS_TEMPERATURE: temperature in °C.
  static const temperature = 'TEMPERATURE';

  // Filter wheel.

  /// FILTER_SLOT: the slot, from 1.
  static const filterSlotValue = 'FILTER_SLOT_VALUE';

  /// FILTER_NAME: the prefix of the name elements, followed by the slot.
  static const filterSlotNamePrefix = 'FILTER_SLOT_NAME_';

  // Dome.

  /// DOME_SHUTTER: open.
  static const shutterOpen = 'SHUTTER_OPEN';

  /// DOME_SHUTTER: close.
  static const shutterClose = 'SHUTTER_CLOSE';

  /// DOME_MOTION: clockwise.
  static const domeClockwise = 'DOME_CW';

  /// DOME_MOTION: counterclockwise.
  static const domeCounterclockwise = 'DOME_CCW';

  /// ABS_DOME_POSITION: azimuth in degrees.
  static const domeAbsolutePosition = 'DOME_ABSOLUTE_POSITION';

  /// DOME_AUTOSYNC: slaving on.
  static const domeAutosyncEnable = 'DOME_AUTOSYNC_ENABLE';

  /// DOME_AUTOSYNC: slaving off.
  static const domeAutosyncDisable = 'DOME_AUTOSYNC_DISABLE';

  // Rotator.

  /// ABS_ROTATOR_ANGLE, SYNC_ROTATOR_ANGLE: angle in degrees.
  static const angle = 'ANGLE';

  // Weather and GPS.

  /// WEATHER_REFRESH, GPS_REFRESH: refresh.
  static const refresh = 'REFRESH';

  // Light box.

  /// FLAT_LIGHT_CONTROL: on.
  static const flatLightOn = 'FLAT_LIGHT_ON';

  /// FLAT_LIGHT_CONTROL: off.
  static const flatLightOff = 'FLAT_LIGHT_OFF';

  /// FLAT_LIGHT_INTENSITY: brightness.
  static const flatLightIntensityValue = 'FLAT_LIGHT_INTENSITY_VALUE';

  // Inputs and outputs.

  /// DIGITAL_INPUT_n, DIGITAL_OUTPUT_n: on.
  static const on = 'ON';

  /// DIGITAL_INPUT_n, DIGITAL_OUTPUT_n: off.
  static const off = 'OFF';

  /// PULSE_n: the pulse length in milliseconds.
  static const duration = 'DURATION';

  // Sky quality meter.

  /// SKY_QUALITY: sky brightness in magnitudes per square arcsecond.
  static const skyBrightness = 'SKY_BRIGHTNESS';

  /// SKY_QUALITY: sensor frequency in Hz.
  static const sensorFrequency = 'SENSOR_FREQUENCY';

  /// SKY_QUALITY: sensor period in counts.
  static const sensorCounts = 'SENSOR_COUNTS';

  /// SKY_QUALITY: sensor period in seconds.
  static const sensorPeriod = 'SENSOR_PERIOD';

  /// SKY_QUALITY: sensor temperature in °C.
  static const skyTemperature = 'SKY_TEMPERATURE';

  // Polar alignment correction.

  /// PAC_MANUAL_ADJUSTMENT: azimuth step in degrees.
  static const manualAzStep = 'MANUAL_AZ_STEP';

  /// PAC_MANUAL_ADJUSTMENT: altitude step in degrees.
  static const manualAltStep = 'MANUAL_ALT_STEP';

  /// PAC_SPEED: speed.
  static const pacSpeedValue = 'PAC_SPEED_VALUE';

  /// PAC_POSITION: azimuth in degrees.
  static const positionAz = 'POSITION_AZ';

  /// PAC_POSITION: altitude in degrees.
  static const positionAlt = 'POSITION_ALT';
}
