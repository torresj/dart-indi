import 'package:indi/indi.dart';
import 'package:test/test.dart';

void main() {
  group('EquatorialCoordinates', () {
    test('parses sexagesimal and decimal text', () {
      final orion = EquatorialCoordinates.parse('05:35:17.3', '-05:23:28');
      expect(orion.raHours, closeTo(5.588139, 1e-6));
      expect(orion.decDegrees, closeTo(-5.391111, 1e-6));
      expect(orion.raDegrees, closeTo(83.822083, 1e-6));
      expect(
        EquatorialCoordinates.parse('12.5', '45'),
        const EquatorialCoordinates(raHours: 12.5, decDegrees: 45),
      );
      expect(
        () => EquatorialCoordinates.parse('x', '0'),
        throwsFormatException,
      );
    });

    test('formats with zero padding and a declination sign', () {
      expect(
        EquatorialCoordinates.parse('05:35:17.3', '-05:23:28').toString(),
        'RA 05:35:17.3 DEC -05:23:28',
      );
      expect(
        const EquatorialCoordinates(raHours: 23.5, decDegrees: 0.5).toString(),
        'RA 23:30:00.0 DEC +00:30:00',
      );
    });
  });

  test('HorizontalCoordinates formats', () {
    expect(
      const HorizontalCoordinates(altitudeDegrees: -2.5, azimuthDegrees: 270)
          .toString(),
      'ALT -02:30:00 AZ 270:00:00',
    );
  });

  test('GeographicLocation converts longitudes for INDI', () {
    const west = GeographicLocation(latitudeDegrees: 0, longitudeDegrees: -3.7);
    expect(west.indiLongitude, closeTo(356.3, 1e-9));
    const east = GeographicLocation(latitudeDegrees: 0, longitudeDegrees: 15);
    expect(east.indiLongitude, 15);
  });

  test('DeviceInterface converts masks', () {
    expect(DeviceInterface.fromMask(0x5),
        {DeviceInterface.telescope, DeviceInterface.guider});
    expect(
      DeviceInterface.toMask({DeviceInterface.ccd, DeviceInterface.guider}),
      6,
    );
    expect(DeviceInterface.fromMask(0), isEmpty);
  });

  test('IndiMessage parses levels', () {
    expect(IndiMessage(text: '[ERROR] Failed').level, IndiMessageLevel.error);
    expect(IndiMessage(text: '[DEBUG] x').level, IndiMessageLevel.debug);
    expect(IndiMessage(text: 'plain').level, IndiMessageLevel.info);
    expect(IndiMessage(text: '[WARNING] Hot').body, 'Hot');
  });
}
