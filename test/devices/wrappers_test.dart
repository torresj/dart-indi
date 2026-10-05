import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:indi/indi.dart';
import 'package:indi/testing.dart';
import 'package:test/test.dart';

import '../support/simulators.dart';

DefSwitchVector _switches(
  String device,
  String name,
  List<String> elements, {
  String? on,
  SwitchRule rule = SwitchRule.oneOfMany,
}) =>
    DefSwitchVector(
      device: device,
      name: name,
      rule: rule,
      elements: [
        for (final element in elements)
          DefSwitch(
            name: element,
            state: element == on ? SwitchState.on : SwitchState.off,
          ),
      ],
    );

DefNumberVector _numbers(
  String device,
  String name,
  Map<String, double> values, {
  double min = 0,
  double max = 0,
}) =>
    DefNumberVector(
      device: device,
      name: name,
      elements: [
        for (final MapEntry(:key, :value) in values.entries)
          DefNumber(name: key, value: value, min: min, max: max),
      ],
    );

/// Answers like a libindi driver: motions go Busy, then Ok with the
/// requested values; exposures go Busy, then send the image.
Future<List<IndiCommand>?> _driver(
  NewVector command,
  FakeIndiServer server,
) async {
  const motions = {
    'EQUATORIAL_EOD_COORD',
    'ABS_FOCUS_POSITION',
    'REL_FOCUS_POSITION',
    'FILTER_SLOT',
    'ABS_DOME_POSITION',
    'ABS_ROTATOR_ANGLE',
    'TELESCOPE_TIMED_GUIDE_NS',
    'TELESCOPE_TIMED_GUIDE_WE',
  };
  if (command is NewNumberVector && motions.contains(command.name)) {
    server.update(SetNumberVector(
      device: command.device,
      name: command.name,
      state: PropertyState.busy,
      elements: const [],
    ));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    var elements = command.elements;
    if (command.name == 'REL_FOCUS_POSITION') {
      final current = server.definition(command.device, 'ABS_FOCUS_POSITION')!
          as DefNumberVector;
      final motion =
          server.definition(command.device, 'FOCUS_MOTION')! as DefSwitchVector;
      final outward = motion.elements
          .firstWhere((e) => e.name == 'FOCUS_OUTWARD')
          .state
          .isOn;
      final steps = command.elements.single.value;
      server.update(SetNumberVector(
        device: command.device,
        name: 'ABS_FOCUS_POSITION',
        state: PropertyState.ok,
        elements: [
          OneNumber(
            name: 'FOCUS_ABSOLUTE_POSITION',
            value: current.elements.single.value + (outward ? steps : -steps),
          ),
        ],
      ));
    }
    if (command.name.startsWith('TELESCOPE_TIMED_GUIDE')) {
      elements = [
        for (final e in elements) OneNumber(name: e.name, value: 0),
      ];
    }
    return [
      SetNumberVector(
        device: command.device,
        name: command.name,
        state: PropertyState.ok,
        elements: elements,
      ),
    ];
  }
  if (command is NewNumberVector && command.name == 'CCD_EXPOSURE') {
    server.update(SetNumberVector(
      device: command.device,
      name: 'CCD_EXPOSURE',
      state: PropertyState.busy,
      elements: command.elements,
    ));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final seconds = command.elements.single.value;
    if (seconds > 100) {
      server.message('[ERROR] Exposure failed', device: command.device);
      return [
        SetNumberVector(
          device: command.device,
          name: 'CCD_EXPOSURE',
          state: PropertyState.alert,
          elements: const [],
        ),
      ];
    }
    return [
      SetBlobVector(
        device: command.device,
        name: 'CCD1',
        state: PropertyState.ok,
        elements: [
          OneBlob(
            name: 'CCD1',
            format: '.fits',
            data: Uint8List.fromList(utf8.encode('SIMPLE  = T $seconds')),
          ),
        ],
      ),
      SetNumberVector(
        device: command.device,
        name: 'CCD_EXPOSURE',
        state: PropertyState.ok,
        elements: const [OneNumber(name: 'CCD_EXPOSURE_VALUE', value: 0)],
      ),
    ];
  }
  return null;
}

void main() {
  late FakeIndiServer server;
  late IndiClient client;

  setUp(() {
    server = FakeIndiServer(onNewVector: _driver);
    client = IndiClient.withTransport(server.transport, options: fastOptions);
  });

  tearDown(() async {
    await client.close();
    await server.close();
  });

  Future<IndiDevice> device(String name, String lastProperty) async {
    if (!client.isConnected) await client.connect();
    final device = await client.waitForDevice(name);
    await device.waitForProperty<IndiProperty>(lastProperty);
    return device;
  }

  group('Telescope', () {
    late Telescope mount;

    setUp(() async {
      defineMount(server);
      server
        ..define(_switches(mountName, 'ON_COORD_SET', ['SLEW', 'TRACK', 'SYNC'],
            on: 'TRACK'))
        ..define(_switches(mountName, 'TELESCOPE_ABORT_MOTION', ['ABORT'],
            rule: SwitchRule.atMostOne))
        ..define(_switches(mountName, 'TELESCOPE_PARK', ['PARK', 'UNPARK'],
            on: 'PARK'))
        ..define(_switches(mountName, 'TELESCOPE_TRACK_MODE',
            ['TRACK_SIDEREAL', 'TRACK_SOLAR', 'TRACK_LUNAR', 'TRACK_CUSTOM'],
            on: 'TRACK_SIDEREAL'))
        ..define(_switches(mountName, 'TELESCOPE_SLEW_RATE',
            ['SLEW_GUIDE', 'SLEW_CENTERING', 'SLEW_FIND', 'SLEW_MAX'],
            on: 'SLEW_MAX'))
        ..define(_switches(
            mountName, 'TELESCOPE_MOTION_NS', ['MOTION_NORTH', 'MOTION_SOUTH'],
            rule: SwitchRule.atMostOne))
        ..define(_switches(
            mountName, 'TELESCOPE_PIER_SIDE', ['PIER_WEST', 'PIER_EAST'],
            on: 'PIER_EAST'))
        ..define(
            _numbers(mountName, 'HORIZONTAL_COORD', {'ALT': 45, 'AZ': 180}))
        ..define(_numbers(mountName, 'GEOGRAPHIC_COORD',
            {'LAT': 40.4, 'LONG': 356.3, 'ELEV': 650}))
        ..define(const DefTextVector(
          device: mountName,
          name: 'TIME_UTC',
          elements: [DefText(name: 'UTC'), DefText(name: 'OFFSET')],
        ))
        ..define(_numbers(mountName, 'TELESCOPE_INFO', {
          'TELESCOPE_APERTURE': 200,
          'TELESCOPE_FOCAL_LENGTH': 1000,
        }))
        ..define(_numbers(mountName, 'TELESCOPE_TIMED_GUIDE_NS',
            {'TIMED_GUIDE_N': 0, 'TIMED_GUIDE_S': 0},
            max: 60000))
        ..define(_numbers(mountName, 'TELESCOPE_TIMED_GUIDE_WE',
            {'TIMED_GUIDE_W': 0, 'TIMED_GUIDE_E': 0},
            max: 60000));
      mount = Telescope(await device(mountName, 'TELESCOPE_TIMED_GUIDE_WE'));
    });

    test('reads the mount state', () {
      expect(mount.coordinates,
          const EquatorialCoordinates(raHours: 5.5, decDegrees: -5.25));
      expect(mount.coordinates.toString(), 'RA 05:30:00.0 DEC -05:15:00');
      expect(
          mount.horizontalCoordinates,
          const HorizontalCoordinates(
              altitudeDegrees: 45, azimuthDegrees: 180));
      expect(mount.isParked, isTrue);
      expect(mount.isTracking, isFalse);
      expect(mount.trackMode, TrackMode.sidereal);
      expect(mount.slewRate, 'SLEW_MAX');
      expect(mount.slewRates, hasLength(4));
      expect(mount.pierSide, PierSide.east);
      expect(mount.location!.longitudeDegrees, closeTo(-3.7, 1e-9));
      expect(mount.location!.elevationMeters, 650);
      expect(mount.aperture, 200);
      expect(mount.focalLength, 1000);
      expect(mount.canPulseGuide, isTrue);
      expect(mount.isSlewing, isFalse);
    });

    test('slewTo selects TRACK and waits for the slew to finish', () async {
      final received = recordReceived(server);
      await mount
          .syncTo(const EquatorialCoordinates(raHours: 1, decDegrees: 2));
      expect(
          server.definition(mountName, 'ON_COORD_SET'),
          isA<DefSwitchVector>().having(
              (d) => d.elements.firstWhere((e) => e.state.isOn).name,
              'on',
              'SYNC'));
      final positions = <EquatorialCoordinates>[];
      mount.coordinatesStream.listen(positions.add);
      await mount.slewTo(
        const EquatorialCoordinates(raHours: 10, decDegrees: 20),
      );
      expect(mount.coordinates,
          const EquatorialCoordinates(raHours: 10, decDegrees: 20));
      expect(mount.isSlewing, isFalse);
      expect(
        received
            .whereType<NewSwitchVector>()
            .map((c) => c.elements.firstWhere((e) => e.state.isOn).name),
        ['SYNC', 'TRACK'],
      );
      await eventually(
          () => positions.isNotEmpty && positions.last.raHours == 10);
    });

    test('slewTo works with drivers without ON_COORD_SET', () async {
      server.delete(mountName, 'ON_COORD_SET');
      await eventually(() => mount.device['ON_COORD_SET'] == null);
      await mount.slewTo(
        const EquatorialCoordinates(raHours: 3, decDegrees: 4),
      );
      expect(mount.coordinates!.raHours, 3);
      await expectLater(
        mount.syncTo(const EquatorialCoordinates(raHours: 3, decDegrees: 4)),
        throwsA(isA<IndiNotFoundException>()),
      );
    });

    test('park, tracking, modes and motion', () async {
      await mount.unpark();
      expect(mount.isParked, isFalse);
      await mount.setTracking(true);
      expect(mount.isTracking, isTrue);
      await mount.setTrackMode(TrackMode.lunar);
      expect(mount.trackMode, TrackMode.lunar);
      await mount.setSlewRate('SLEW_GUIDE');
      expect(mount.slewRate, 'SLEW_GUIDE');
      await mount.startMotion(GuideDirection.north);
      expect(
          mount.device.getSwitch('TELESCOPE_MOTION_NS')!.isOn('MOTION_NORTH'),
          isTrue);
      await mount.stopMotion(GuideDirection.north);
      expect(
          mount.device.getSwitch('TELESCOPE_MOTION_NS')!.isOn('MOTION_NORTH'),
          isFalse);
      await mount.abort();
      await mount.park();
      expect(mount.isParked, isTrue);
    });

    test('pulse guides', () async {
      final received = recordReceived(server);
      await mount.pulseGuide(
        GuideDirection.east,
        const Duration(milliseconds: 500),
      );
      expect(
        received.whereType<NewNumberVector>().single.elements,
        const [
          OneNumber(name: 'TIMED_GUIDE_W', value: 0),
          OneNumber(name: 'TIMED_GUIDE_E', value: 500),
        ],
      );
    });

    test('sets the site and time', () async {
      await mount.setLocation(const GeographicLocation(
        latitudeDegrees: 28.76,
        longitudeDegrees: -17.88,
        elevationMeters: 2396,
      ));
      expect(
          server.definition(mountName, 'GEOGRAPHIC_COORD'),
          isA<DefNumberVector>().having(
              (d) => d.elements[1].value, 'LONG', closeTo(342.12, 1e-9)));
      await mount.setTime(
        DateTime.utc(2026, 10, 4, 22),
        utcOffset: const Duration(hours: 1),
      );
      final time = server.definition(mountName, 'TIME_UTC')! as DefTextVector;
      expect(
          time.elements.map((e) => e.value), ['2026-10-04T22:00:00', '1.00']);
    });
  });

  group('Camera', () {
    late Camera camera;

    setUp(() async {
      defineCamera(server);
      server
        ..define(_switches(cameraName, 'CCD_ABORT_EXPOSURE', ['ABORT'],
            rule: SwitchRule.atMostOne))
        ..define(_numbers(
            cameraName, 'CCD_BINNING', {'HOR_BIN': 1, 'VER_BIN': 1},
            min: 1, max: 4))
        ..define(_numbers(cameraName, 'CCD_FRAME',
            {'X': 0, 'Y': 0, 'WIDTH': 1280, 'HEIGHT': 1024}))
        ..define(_numbers(cameraName, 'CCD_INFO', {
          'CCD_MAX_X': 1280,
          'CCD_MAX_Y': 1024,
          'CCD_PIXEL_SIZE': 5.2,
          'CCD_PIXEL_SIZE_X': 5.2,
          'CCD_PIXEL_SIZE_Y': 5.2,
          'CCD_BITSPERPIXEL': 16,
        }))
        ..define(_switches(
            cameraName, 'CCD_COOLER', ['COOLER_ON', 'COOLER_OFF'],
            on: 'COOLER_OFF'))
        ..define(_numbers(
            cameraName, 'CCD_CONTROLS', {'Gain': 100, 'Offset': 10},
            max: 500))
        ..define(_switches(cameraName, 'UPLOAD_MODE',
            ['UPLOAD_CLIENT', 'UPLOAD_LOCAL', 'UPLOAD_BOTH'],
            on: 'UPLOAD_LOCAL'))
        ..define(_switches(
            cameraName, 'CCD_TRANSFER_FORMAT', ['FORMAT_FITS', 'FORMAT_NATIVE'],
            on: 'FORMAT_FITS'))
        ..define(_switches(
            cameraName, 'CCD_COMPRESSION', ['INDI_ENABLED', 'INDI_DISABLED'],
            on: 'INDI_DISABLED'));
      camera = Camera(await device(cameraName, 'CCD_COMPRESSION'));
    });

    test('reads the camera state', () {
      expect(camera.frameType, FrameType.light);
      expect(camera.binning, (1, 1));
      expect(camera.frame,
          const SensorFrame(x: 0, y: 0, width: 1280, height: 1024));
      expect(
          camera.sensorInfo,
          const SensorInfo(
            width: 1280,
            height: 1024,
            pixelSizeX: 5.2,
            pixelSizeY: 5.2,
            bitsPerPixel: 16,
          ));
      expect(camera.temperature, 20);
      expect(camera.isCoolerOn, isFalse);
      expect(camera.gain, 100);
      expect(camera.offset, 10);
      expect(camera.uploadMode, UploadMode.local);
      expect(camera.transferFormat, TransferFormat.fits);
      expect(camera.isCompressed, isFalse);
      expect(camera.isExposing, isFalse);
      expect(camera.exposureRemaining, isNull);
    });

    test('expose configures, enables images and returns the image', () async {
      final image = await camera.expose(
        const Duration(milliseconds: 1500),
        frameType: FrameType.dark,
        binning: 2,
      );
      expect(utf8.decode(image.bytes), 'SIMPLE  = T 1.5');
      expect(image.format, '.fits');
      expect(camera.frameType, FrameType.dark);
      expect(camera.binning, (2, 2));
      expect(camera.uploadMode, UploadMode.both);
      expect(
          client.blobMode(device: cameraName, property: 'CCD1'), BlobMode.also);
    });

    test('expose fails when the camera reports an error', () async {
      await expectLater(
        camera.expose(const Duration(seconds: 200)),
        throwsA(isA<IndiPropertyAlertException>()
            .having((e) => e.message, 'message', contains('Exposure failed'))),
      );
    });

    test('expose fails when the connection is lost', () async {
      server.onNewVector = (command, server) async {
        if (command.name == 'CCD_EXPOSURE') {
          await server.dropConnections();
          return const [];
        }
        return null;
      };
      await expectLater(
        camera.expose(const Duration(seconds: 1)),
        throwsA(isA<IndiConnectionLostException>()),
      );
    });

    test('images streams every new image', () async {
      final images = <IndiBlob>[];
      camera.images.listen(images.add);
      await camera.expose(const Duration(seconds: 1));
      await camera.expose(const Duration(seconds: 2));
      await eventually(() => images.length == 2);
      expect(utf8.decode(images.last.bytes), contains('T 2'));
    });

    test('settings', () async {
      await camera.setFrame(
        const SensorFrame(x: 10, y: 20, width: 100, height: 200),
      );
      expect(camera.frame!.width, 100);
      await camera.setCooler(true);
      expect(camera.isCoolerOn, isTrue);
      await camera.setTemperature(-10);
      await eventually(() => camera.temperature == -10);
      await camera.setGain(150);
      expect(camera.gain, 150);
      await camera.setOffset(20);
      expect(camera.offset, 20);
      await camera.setTransferFormat(TransferFormat.native);
      expect(camera.transferFormat, TransferFormat.native);
      await camera.setCompression(true);
      expect(camera.isCompressed, isTrue);
      await camera.abortExposure();
    });
  });

  group('Focuser', () {
    late Focuser focuser;

    setUp(() async {
      const name = 'Focuser Simulator';
      server
        ..define(connection(name))
        ..define(_numbers(
            name, 'ABS_FOCUS_POSITION', {'FOCUS_ABSOLUTE_POSITION': 50000},
            max: 100000))
        ..define(_numbers(
            name, 'REL_FOCUS_POSITION', {'FOCUS_RELATIVE_POSITION': 0},
            max: 100000))
        ..define(_switches(
            name, 'FOCUS_MOTION', ['FOCUS_INWARD', 'FOCUS_OUTWARD'],
            on: 'FOCUS_INWARD'))
        ..define(_switches(name, 'FOCUS_ABORT_MOTION', ['ABORT'],
            rule: SwitchRule.atMostOne))
        ..define(_numbers(name, 'FOCUS_MAX', {'FOCUS_MAX_VALUE': 100000}))
        ..define(_numbers(name, 'FOCUS_TEMPERATURE', {'TEMPERATURE': 12.5}))
        ..define(
            _numbers(name, 'FOCUS_SYNC', {'FOCUS_SYNC_VALUE': 0}, max: 100000));
      focuser = Focuser(await device(name, 'FOCUS_SYNC'));
    });

    test('moves to absolute and relative positions', () async {
      expect(focuser.position, 50000);
      expect(focuser.maxPosition, 100000);
      expect(focuser.temperature, 12.5);
      await focuser.moveTo(42000);
      expect(focuser.position, 42000);
      await focuser.moveBy(500);
      await eventually(() => focuser.position == 42500);
      await focuser.moveBy(-1000);
      await eventually(() => focuser.position == 41500);
      expect(focuser.isMoving, isFalse);
      await focuser.moveBy(0);
      await focuser.sync(0);
      await focuser.abort();
    });
  });

  group('FilterWheel', () {
    late FilterWheel wheel;

    setUp(() async {
      const name = 'Filter Simulator';
      server
        ..define(connection(name))
        ..define(_numbers(name, 'FILTER_SLOT', {'FILTER_SLOT_VALUE': 1},
            min: 1, max: 5))
        ..define(const DefTextVector(
          device: name,
          name: 'FILTER_NAME',
          elements: [
            DefText(name: 'FILTER_SLOT_NAME_1', value: 'Red'),
            DefText(name: 'FILTER_SLOT_NAME_2', value: 'Green'),
            DefText(name: 'FILTER_SLOT_NAME_3', value: 'Blue'),
            DefText(name: 'FILTER_SLOT_NAME_4', value: 'Ha'),
            DefText(name: 'FILTER_SLOT_NAME_5', value: 'OIII'),
          ],
        ));
      wheel = FilterWheel(await device(name, 'FILTER_NAME'));
    });

    test('selects filters by slot and by name', () async {
      expect(wheel.filterNames, ['Red', 'Green', 'Blue', 'Ha', 'OIII']);
      expect(wheel.slotCount, 5);
      expect(wheel.currentFilter, 'Red');
      await wheel.selectFilter('ha');
      expect(wheel.slot, 4);
      expect(wheel.currentFilter, 'Ha');
      await wheel.selectSlot(2);
      expect(wheel.currentFilter, 'Green');
      expect(
          () => wheel.selectFilter('L'), throwsA(isA<IndiNotFoundException>()));
      await wheel.setFilterNames(['L', 'R', 'G', 'B', 'Ha']);
      await eventually(() => wheel.filterNames.first == 'L');
    });
  });

  group('Dome, Rotator, Weather, GPS, DustCap and LightBox', () {
    test('Dome', () async {
      const name = 'Dome Simulator';
      server
        ..define(_switches(
            name, 'DOME_SHUTTER', ['SHUTTER_OPEN', 'SHUTTER_CLOSE'],
            on: 'SHUTTER_CLOSE'))
        ..define(_numbers(
            name, 'ABS_DOME_POSITION', {'DOME_ABSOLUTE_POSITION': 0},
            max: 360))
        ..define(_switches(name, 'DOME_PARK', ['PARK', 'UNPARK'], on: 'PARK'))
        ..define(_switches(name, 'DOME_AUTOSYNC',
            ['DOME_AUTOSYNC_ENABLE', 'DOME_AUTOSYNC_DISABLE'],
            on: 'DOME_AUTOSYNC_DISABLE'))
        ..define(_switches(name, 'DOME_ABORT_MOTION', ['ABORT'],
            rule: SwitchRule.atMostOne));
      final dome = Dome(await device(name, 'DOME_ABORT_MOTION'));
      expect(dome.shutterState, ShutterState.closed);
      await dome.openShutter();
      expect(dome.shutterState, ShutterState.open);
      await dome.unpark();
      expect(dome.isParked, isFalse);
      await dome.moveTo(90);
      expect(dome.azimuth, 90);
      await dome.setSlaving(true);
      expect(dome.isSlaved, isTrue);
      await dome.abort();
      await dome.closeShutter();
      expect(dome.shutterState, ShutterState.closed);
    });

    test('Rotator', () async {
      const name = 'Rotator Simulator';
      server
        ..define(_numbers(name, 'ABS_ROTATOR_ANGLE', {'ANGLE': 0}, max: 360))
        ..define(_numbers(name, 'SYNC_ROTATOR_ANGLE', {'ANGLE': 0}, max: 360));
      final rotator = Rotator(await device(name, 'SYNC_ROTATOR_ANGLE'));
      await rotator.moveTo(45);
      expect(rotator.angle, 45);
      expect(rotator.isMoving, isFalse);
      await rotator.sync(50);
    });

    test('Weather', () async {
      const name = 'Weather Simulator';
      server
        ..define(const DefLightVector(
          device: name,
          name: 'WEATHER_STATUS',
          state: PropertyState.ok,
          elements: [
            DefLight(name: 'WEATHER_RAIN_HOUR', state: PropertyState.ok),
            DefLight(name: 'WEATHER_WIND_SPEED', state: PropertyState.busy),
          ],
        ))
        ..define(_numbers(name, 'WEATHER_PARAMETERS', {
          'WEATHER_TEMPERATURE': 8.5,
          'WEATHER_WIND_SPEED': 25,
        }))
        ..define(_switches(name, 'WEATHER_REFRESH', ['REFRESH'],
            rule: SwitchRule.atMostOne));
      final weather = Weather(await device(name, 'WEATHER_REFRESH'));
      expect(weather.isSafe, isTrue);
      expect(weather.statuses['WEATHER_WIND_SPEED'], PropertyState.busy);
      expect(weather.parameters['WEATHER_TEMPERATURE'], 8.5);
      final statuses = <PropertyState>[];
      weather.statusStream.listen(statuses.add);
      server.update(const SetLightVector(
        device: name,
        name: 'WEATHER_STATUS',
        state: PropertyState.alert,
        elements: [],
      ));
      await eventually(() => statuses.length == 2);
      expect(statuses, [PropertyState.ok, PropertyState.alert]);
      expect(weather.isSafe, isFalse);
      await weather.refresh();
    });

    test('Gps', () async {
      const name = 'GPS Simulator';
      server
        ..define(_numbers(
            name, 'GEOGRAPHIC_COORD', {'LAT': 51.48, 'LONG': 0, 'ELEV': 46}))
        ..define(const DefTextVector(
          device: name,
          name: 'TIME_UTC',
          elements: [
            DefText(name: 'UTC', value: '2026-10-04T21:00:00'),
            DefText(name: 'OFFSET', value: '0'),
          ],
        ));
      final gps = Gps(await device(name, 'TIME_UTC'));
      expect(gps.location!.latitudeDegrees, 51.48);
      expect(gps.time, DateTime.utc(2026, 10, 4, 21));
      expect(await gps.locationStream.first, gps.location);
    });

    test('DustCap and LightBox', () async {
      const name = 'Flip Flat';
      server
        ..define(_switches(name, 'CAP_PARK', ['PARK', 'UNPARK'], on: 'UNPARK'))
        ..define(_switches(
            name, 'FLAT_LIGHT_CONTROL', ['FLAT_LIGHT_ON', 'FLAT_LIGHT_OFF'],
            on: 'FLAT_LIGHT_OFF'))
        ..define(_numbers(
            name, 'FLAT_LIGHT_INTENSITY', {'FLAT_LIGHT_INTENSITY_VALUE': 0},
            max: 255));
      final panel = await device(name, 'FLAT_LIGHT_INTENSITY');
      final cap = DustCap(panel);
      final light = LightBox(panel);
      expect(cap.isClosed, isFalse);
      await cap.close();
      expect(cap.isClosed, isTrue);
      await light.setLight(true);
      expect(light.isOn, isTrue);
      await light.setBrightness(128);
      expect(light.brightness, 128);
      await cap.open();
      expect(cap.isClosed, isFalse);
    });
  });

  group('IndiDeviceWrapper', () {
    test('common settings', () async {
      server
        ..define(connection('Generic'))
        ..define(const DefTextVector(
          device: 'Generic',
          name: 'DEVICE_PORT',
          elements: [DefText(name: 'PORT', value: '/dev/ttyUSB0')],
        ))
        ..define(_switches('Generic', 'CONFIG_PROCESS',
            ['CONFIG_LOAD', 'CONFIG_SAVE', 'CONFIG_DEFAULT', 'CONFIG_PURGE'],
            rule: SwitchRule.atMostOne))
        ..define(_numbers('Generic', 'POLLING_PERIOD', {'PERIOD_MS': 1000},
            max: 60000))
        ..define(
            _switches('Generic', 'DEBUG', ['ENABLE', 'DISABLE'], on: 'DISABLE'))
        ..define(_switches('Generic', 'SIMULATION', ['ENABLE', 'DISABLE'],
            on: 'DISABLE'));
      final wrapper = Guider(await device('Generic', 'SIMULATION'));
      expect(wrapper.name, 'Generic');
      expect(wrapper.client, same(client));
      expect(wrapper.isAvailable, isTrue);
      expect(wrapper.canPulseGuide, isFalse);
      expect(wrapper.toString(), 'Guider(Generic)');
      await wrapper.connect();
      expect(wrapper.isConnected, isTrue);
      await wrapper.setPort('/dev/ttyACM0');
      await wrapper.saveConfig();
      await wrapper.loadConfig();
      await wrapper.setPollingPeriod(const Duration(milliseconds: 500));
      await wrapper.setDebug(true);
      await wrapper.setSimulation(true);
      await wrapper.disconnect();
      expect(wrapper.isConnected, isFalse);
      expect(
        (server.definition('Generic', 'POLLING_PERIOD')! as DefNumberVector)
            .elements
            .single
            .value,
        500,
      );
    });
  });
}
