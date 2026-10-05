import 'package:flutter/material.dart';
import 'package:indi/indi.dart';

import 'device_screen.dart';

/// Lists the devices of the server, with the connection state.
class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key, required this.client});

  final IndiClient client;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),
        actions: [
          _ConnectionChip(client: client),
          IconButton(
            tooltip: 'Messages',
            icon: const Icon(Icons.notes),
            onPressed: () => _showMessages(context),
          ),
        ],
      ),
      body: StreamBuilder<IndiEvent>(
        // Rebuild when devices come and go, or connect and disconnect.
        stream: client.events.where(
          (event) =>
              event is DeviceAdded ||
              event is DeviceRemoved ||
              event is ConnectionStateChanged ||
              event is SessionResumed ||
              (event is PropertyEvent &&
                  (event.property.name == StandardProperties.connection ||
                      event.property.name == StandardProperties.driverInfo)),
        ),
        builder: (context, _) {
          final devices = client.devices.values.toList();
          if (devices.isEmpty) {
            return const Center(child: Text('Waiting for devices…'));
          }
          return ListView(
            children: [
              for (final device in devices)
                ListTile(
                  leading: Icon(
                    device.isConnected ? Icons.link : Icons.link_off,
                    color: device.isConnected ? Colors.green : null,
                  ),
                  title: Text(device.name),
                  subtitle: Text(
                    device.interfaces.map((i) => i.name).join(', '),
                  ),
                  enabled: device.isAvailable,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => DeviceScreen(device: device),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _showMessages(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => StreamBuilder<MessageReceived>(
        stream: client.eventsOf<MessageReceived>(),
        builder: (context, _) {
          final messages = client.messages.reversed.toList();
          return ListView(
            children: [
              for (final message in messages)
                ListTile(
                  dense: true,
                  title: Text(message.body),
                  subtitle: Text(
                    '${message.device ?? 'Server'} · '
                    '${message.timestamp.toLocal()}',
                  ),
                  leading: Icon(switch (message.level) {
                    IndiMessageLevel.error => Icons.error,
                    IndiMessageLevel.warning => Icons.warning,
                    _ => Icons.info_outline,
                  }),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip({required this.client});

  final IndiClient client;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<IndiConnectionState>(
      stream: client.connectionStates,
      initialData: client.connectionState,
      builder: (context, snapshot) {
        final (label, color) = switch (snapshot.requireData) {
          IndiConnected() => ('Online', Colors.green),
          IndiConnecting() => ('Connecting', Colors.amber),
          IndiReconnecting(:final delay) => (
              'Retry in ${delay.inSeconds}s',
              Colors.amber,
            ),
          IndiDisconnected() => ('Offline', Colors.red),
          IndiClosed() => ('Closed', Colors.grey),
        };
        return Chip(
          avatar: Icon(Icons.circle, size: 12, color: color),
          label: Text(label),
        );
      },
    );
  }
}
