import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indi/indi.dart';
import 'package:indi/testing.dart';
import 'package:indi_example/src/devices_screen.dart';

void main() {
  testWidgets('shows devices and changes a switch', (tester) async {
    final server = FakeIndiServer()
      ..define(const DefSwitchVector(
        device: 'Telescope Simulator',
        name: 'CONNECTION',
        label: 'Connection',
        group: 'Main Control',
        rule: SwitchRule.oneOfMany,
        elements: [
          DefSwitch(name: 'CONNECT', label: 'Connect', state: SwitchState.off),
          DefSwitch(
            name: 'DISCONNECT',
            label: 'Disconnect',
            state: SwitchState.on,
          ),
        ],
      ))
      ..define(const DefNumberVector(
        device: 'Telescope Simulator',
        name: 'EQUATORIAL_EOD_COORD',
        label: 'Eq. Coordinates',
        group: 'Main Control',
        elements: [
          DefNumber(name: 'RA', format: '%010.6m', max: 24, value: 5.5),
          DefNumber(name: 'DEC', format: '%010.6m', min: -90, max: 90),
        ],
      ));
    final client = IndiClient.withTransport(
      server.transport,
      options: const IndiClientOptions(
        heartbeat: HeartbeatOptions.disabled(),
      ),
    );

    await tester.runAsync(() async {
      await client.connect();
      final device = await client.waitForDevice('Telescope Simulator');
      await device.waitForProperty<NumberProperty>('EQUATORIAL_EOD_COORD');
    });
    await tester.pumpWidget(MaterialApp(home: DevicesScreen(client: client)));
    await tester.pump();
    expect(find.text('Telescope Simulator'), findsOneWidget);

    await tester.tap(find.text('Telescope Simulator'));
    await tester.pumpAndSettle();
    expect(find.text('Eq. Coordinates'), findsOneWidget);
    expect(find.text('5:30:00'), findsOneWidget);

    await tester.tap(find.text('Connect'));
    await tester.runAsync(
      () => client.waitFor(
        () => client.device('Telescope Simulator')!.isConnected,
      ),
    );
    await tester.pump();
    final chip = tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, 'Connect'),
    );
    expect(chip.selected, isTrue);

    await tester.runAsync(() async {
      await client.close();
      await server.close();
    });
  });
}

extension on IndiClient {
  Future<void> waitFor(bool Function() condition) async {
    while (!condition()) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }
}
