import 'package:flutter/material.dart';
import 'package:indi/indi.dart';

import 'state_colors.dart';

/// Shows one property and lets the user change it, whatever its type.
class PropertyCard extends StatelessWidget {
  const PropertyCard({super.key, required this.device, required this.name});

  final IndiDevice device;
  final String name;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<IndiProperty>(
      stream: device.watch<IndiProperty>(name),
      initialData: device[name],
      builder: (context, snapshot) {
        final property = snapshot.data;
        if (property == null) return const SizedBox.shrink();
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    StateDot(property.state),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        property.label,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    if (property.permission == PropertyPermission.readOnly)
                      const Icon(Icons.lock_outline, size: 16),
                  ],
                ),
                const SizedBox(height: 8),
                switch (property) {
                  NumberProperty() => _NumberEditor(device, property),
                  TextProperty() => _TextEditor(device, property),
                  SwitchProperty() => _SwitchButtons(device, property),
                  LightProperty() => _Lights(property),
                  BlobProperty() => _BlobInfo(device, property),
                },
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Runs [command] and shows its error, if any, in a snack bar.
Future<void> _run(BuildContext context, Future<void> Function() command) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await command();
  } on IndiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

/// Edits the values of a number or text property, sending them together.
abstract class _ValuesEditor<P extends IndiProperty> extends StatefulWidget {
  const _ValuesEditor(this.device, this.property);

  final IndiDevice device;
  final P property;
}

abstract class _ValuesEditorState<P extends IndiProperty>
    extends State<_ValuesEditor<P>> {
  final Map<String, TextEditingController> _controllers = {};

  TextEditingController controllerFor(String element) =>
      _controllers.putIfAbsent(element, TextEditingController.new);

  Future<void> send(Map<String, String> edited);

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget buildEditor({
    required List<(String name, String label, String value)> rows,
  }) {
    final writable = widget.property.permission.canWrite;
    return Column(
      children: [
        for (final (name, label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Expanded(flex: 3, child: Text(label)),
                Expanded(flex: 3, child: Text(value)),
                if (writable)
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: controllerFor(name),
                      decoration: const InputDecoration(isDense: true),
                    ),
                  ),
              ],
            ),
          ),
        if (writable)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                final edited = {
                  for (final MapEntry(:key, :value) in _controllers.entries)
                    if (value.text.trim().isNotEmpty) key: value.text.trim(),
                };
                if (edited.isEmpty) return;
                _run(context, () => send(edited));
              },
              child: const Text('Set'),
            ),
          ),
      ],
    );
  }
}

class _NumberEditor extends _ValuesEditor<NumberProperty> {
  const _NumberEditor(super.device, super.property);

  @override
  State<_ValuesEditor<NumberProperty>> createState() => _NumberEditorState();
}

class _NumberEditorState extends _ValuesEditorState<NumberProperty> {
  @override
  Future<void> send(Map<String, String> edited) async {
    final values = <String, num>{};
    for (final MapEntry(:key, :value) in edited.entries) {
      // Accepts sexagesimal input such as 05:35:17.
      final number = parseIndiNumber(value);
      if (number == null) {
        throw IndiValidationException('"$value" is not a number');
      }
      values[key] = number;
    }
    await widget.device.sendNumbers(widget.property.name, values);
    for (final controller in _controllers.values) {
      controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) => buildEditor(rows: [
        for (final element in widget.property.elements)
          (element.name, element.label, element.formattedValue.trim()),
      ]);
}

class _TextEditor extends _ValuesEditor<TextProperty> {
  const _TextEditor(super.device, super.property);

  @override
  State<_ValuesEditor<TextProperty>> createState() => _TextEditorState();
}

class _TextEditorState extends _ValuesEditorState<TextProperty> {
  @override
  Future<void> send(Map<String, String> edited) async {
    await widget.device.sendTexts(widget.property.name, edited);
    for (final controller in _controllers.values) {
      controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) => buildEditor(rows: [
        for (final element in widget.property.elements)
          (element.name, element.label, element.value),
      ]);
}

class _SwitchButtons extends StatelessWidget {
  const _SwitchButtons(this.device, this.property);

  final IndiDevice device;
  final SwitchProperty property;

  @override
  Widget build(BuildContext context) {
    final writable = property.permission.canWrite;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final element in property.elements)
          FilterChip(
            label: Text(element.label),
            selected: element.isOn,
            onSelected: !writable
                ? null
                : (selected) {
                    // A OneOfMany property can't have every switch off.
                    if (!selected && property.rule == SwitchRule.oneOfMany) {
                      return;
                    }
                    _run(
                      context,
                      () => device.setSwitch(
                        property.name,
                        element.name,
                        on: selected,
                      ),
                    );
                  },
          ),
      ],
    );
  }
}

class _Lights extends StatelessWidget {
  const _Lights(this.property);

  final LightProperty property;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        for (final light in property.elements)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StateDot(light.state),
              const SizedBox(width: 4),
              Text(light.label),
            ],
          ),
      ],
    );
  }
}

class _BlobInfo extends StatefulWidget {
  const _BlobInfo(this.device, this.property);

  final IndiDevice device;
  final BlobProperty property;

  @override
  State<_BlobInfo> createState() => _BlobInfoState();
}

class _BlobInfoState extends State<_BlobInfo> {
  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    final property = widget.property;
    final enabled = device.client.blobMode(
          device: device.name,
          property: property.name,
        ) !=
        BlobMode.never;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final element in property.elements)
          Text(
            '${element.label}: ${switch (element.blob) {
              null => 'no data yet',
              final blob => '${blob.format}, ${blob.bytes.length} bytes',
            }}',
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Receive data'),
          value: enabled,
          onChanged: (on) async {
            await _run(
              context,
              () => device.setBlobMode(
                on ? BlobMode.also : BlobMode.never,
                property: property.name,
              ),
            );
            if (mounted) setState(() {});
          },
        ),
      ],
    );
  }
}
