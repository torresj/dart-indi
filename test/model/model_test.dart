import 'dart:typed_data';

import 'package:indi/indi.dart';
import 'package:indi/src/model/property_updates.dart';
import 'package:indi/testing.dart';
import 'package:test/test.dart';

/// Checks equality, hashCode and toString of two equal and one different
/// value.
void expectValueSemantics(Object a, Object sameAsA, Object different) {
  expect(a, sameAsA);
  expect(a.hashCode, sameAsA.hashCode);
  expect(a, isNot(different));
  expect(a.toString(), isNotEmpty);
}

NumberProperty numbers({PropertyState state = PropertyState.idle}) =>
    NumberProperty(
      device: 'd',
      name: 'N',
      state: state,
      elements: const [
        NumberElement(name: 'x', value: 1, min: 0, max: 10, format: '%.1f'),
        NumberElement(name: 'y', value: 2),
      ],
    );

void main() {
  group('elements and properties', () {
    test('have value semantics', () {
      expectValueSemantics(
          numbers(), numbers(), numbers(state: PropertyState.ok));
      expectValueSemantics(
        const TextElement(name: 't', value: 'a'),
        const TextElement(name: 't', value: 'a'),
        const TextElement(name: 't', value: 'b'),
      );
      expectValueSemantics(
        const SwitchElement(name: 's', state: SwitchState.on),
        const SwitchElement(name: 's', state: SwitchState.on),
        const SwitchElement(name: 's', state: SwitchState.off),
      );
      expectValueSemantics(
        const LightElement(name: 'l', state: PropertyState.ok),
        const LightElement(name: 'l', state: PropertyState.ok),
        const LightElement(name: 'l', state: PropertyState.alert),
      );
      expect(numbers().toString(), contains('NumberProperty(device: '));
      expect(numbers().toString(), contains("name: 'x'"));
    });

    test('BLOB elements compare their data by identity', () {
      final blob = IndiBlob(Uint8List.fromList([1, 2]), format: '.fits');
      final same = BlobElement(name: 'b', blob: blob);
      expectValueSemantics(
        same,
        BlobElement(name: 'b', blob: blob),
        BlobElement(
          name: 'b',
          blob: IndiBlob(Uint8List.fromList([1, 2]), format: '.fits'),
        ),
      );
      expect(same.toString(), contains('IndiBlob(.fits, 2 bytes)'));
    });

    test('look up elements', () {
      final property = numbers();
      expect(property.elementNames, ['x', 'y']);
      expect(property['x']!.formattedValue, '1.0');
      expect(property['x']!.hasRange, isTrue);
      expect(property['y']!.hasRange, isFalse);
      expect(property['nope'], isNull);
      expect(
        () => property.element('nope'),
        throwsA(isA<IndiNotFoundException>()
            .having((e) => e.message, 'message', contains('d.N'))),
      );
      expect(property.label, 'N');
      expect(property.isBusy, isFalse);
    });

    test('switch properties report active elements', () {
      final property = SwitchProperty(
        device: 'd',
        name: 'S',
        rule: SwitchRule.anyOfMany,
        elements: const [
          SwitchElement(name: 'a', state: SwitchState.on),
          SwitchElement(name: 'b', state: SwitchState.off),
          SwitchElement(name: 'c', state: SwitchState.on),
        ],
      );
      expect(property.activeElements.map((e) => e.name), ['a', 'c']);
      expect(property.activeElement?.name, 'a');
      expect(property.isOn('b'), isFalse);
      expect(property.isOn('nope'), isFalse);
    });

    test('permissions', () {
      expect(PropertyPermission.readOnly.canRead, isTrue);
      expect(PropertyPermission.readOnly.canWrite, isFalse);
      expect(PropertyPermission.writeOnly.canRead, isFalse);
      expect(PropertyPermission.readWrite.canWrite, isTrue);
      expect(SwitchState.fromBool(true), SwitchState.on);
      expect(SwitchState.on.isOn, isTrue);
    });
  });

  group('property updates', () {
    test('withState changes only the state, for every type', () {
      final properties = <IndiProperty>[
        numbers(),
        TextProperty(
          device: 'd',
          name: 'T',
          elements: const [TextElement(name: 't')],
        ),
        SwitchProperty(
          device: 'd',
          name: 'S',
          elements: const [SwitchElement(name: 's', state: SwitchState.off)],
        ),
        LightProperty(
          device: 'd',
          name: 'L',
          elements: const [LightElement(name: 'l', state: PropertyState.ok)],
        ),
        BlobProperty(
          device: 'd',
          name: 'B',
          elements: const [BlobElement(name: 'b')],
        ),
      ];
      for (final property in properties) {
        final busy = withState(property, PropertyState.busy);
        expect(busy.state, PropertyState.busy, reason: property.name);
        expect(busy.runtimeType, property.runtimeType);
        expect(busy.elements, property.elements);
        expect(identical(withState(busy, PropertyState.busy), busy), isTrue);
      }
    });

    test('number updates keep the other elements and their ranges', () {
      final updated = applyUpdate(
        numbers(),
        const SetNumberVector(
          device: 'd',
          name: 'N',
          state: PropertyState.ok,
          elements: [OneNumber(name: 'y', value: 5)],
        ),
      )! as NumberProperty;
      expect(updated.state, PropertyState.ok);
      expect(updated['x'], numbers()['x']);
      expect(updated['y']!.value, 5);
    });

    test('updates keep elements that are not in the update', () {
      final lights = LightProperty(
        device: 'd',
        name: 'L',
        elements: const [
          LightElement(name: 'a', state: PropertyState.ok),
          LightElement(name: 'b', state: PropertyState.ok),
        ],
      );
      final updated = applyUpdate(
        lights,
        const SetLightVector(
          device: 'd',
          name: 'L',
          elements: [OneLight(name: 'b', state: PropertyState.alert)],
        ),
      )! as LightProperty;
      expect(updated.elements.map((e) => e.state),
          [PropertyState.ok, PropertyState.alert]);

      final blobs = BlobProperty(
        device: 'd',
        name: 'B',
        elements: const [BlobElement(name: 'a'), BlobElement(name: 'b')],
      );
      final withBlob = applyUpdate(
        blobs,
        SetBlobVector(
          device: 'd',
          name: 'B',
          elements: [
            OneBlob(name: 'b', format: '.jpg', data: Uint8List.fromList([9])),
          ],
        ),
      )! as BlobProperty;
      expect(withBlob['a']!.blob, isNull);
      expect(withBlob['b']!.blob!.format, '.jpg');
    });

    test('an update of the wrong type is rejected', () {
      expect(
        applyUpdate(
          numbers(),
          const SetTextVector(device: 'd', name: 'N', elements: []),
        ),
        isNull,
      );
    });
  });

  group('IndiBlob', () {
    test('describes its format', () {
      final plain = IndiBlob(Uint8List(3), format: '.fits');
      expect(plain.isCompressed, isFalse);
      expect(plain.uncompressedFormat, '.fits');
      expect(plain.decompress(), same(plain.bytes));
      expect(plain.size, 3);
      expect(plain.toString(), 'IndiBlob(.fits, 3 bytes)');
      final compressed = IndiBlob(Uint8List(3), format: '.fits.z', size: 100);
      expect(compressed.isCompressed, isTrue);
      expect(compressed.uncompressedFormat, '.fits');
      expect(compressed.size, 100);
    });
  });

  group('IndiMessage', () {
    test('has value semantics', () {
      final time = DateTime.utc(2026);
      expectValueSemantics(
        IndiMessage(device: 'd', text: 'hi', timestamp: time),
        IndiMessage(device: 'd', text: 'hi', timestamp: time),
        IndiMessage(text: 'hi', timestamp: time),
      );
      expect(IndiMessage(text: 'x', timestamp: time).toString(),
          'IndiMessage(2026-01-01 00:00:00.000Z: x)');
      expect(IndiMessage(device: 'd', text: 'x', timestamp: time).toString(),
          contains('IndiMessage(d, '));
      expect(IndiMessage(text: 'now').timestamp.isUtc, isTrue);
    });
  });
}
