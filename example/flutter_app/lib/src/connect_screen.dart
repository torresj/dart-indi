import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:indi/indi.dart';

import 'devices_screen.dart';

/// Asks for the server address and connects.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _host = TextEditingController(text: 'localhost');
  // On the web, connect to a WebSocket bridge such as websockify.
  final _port = TextEditingController(text: kIsWeb ? '8624' : '7624');
  bool _connecting = false;
  String? _error;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final port = int.tryParse(_port.text.trim());
    if (port == null) {
      setState(() => _error = 'Invalid port');
      return;
    }
    setState(() {
      _connecting = true;
      _error = null;
    });
    final client = IndiClient(
      host: _host.text.trim(),
      port: port,
      options: const IndiClientOptions(separateBlobConnection: true),
    );
    try {
      await client.connect();
    } on IndiException catch (e) {
      await client.close();
      setState(() {
        _connecting = false;
        _error = e.message;
      });
      return;
    }
    if (!mounted) return;
    setState(() => _connecting = false);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ReconnectOnResume(
          client: client,
          child: DevicesScreen(client: client),
        ),
      ),
    );
    await client.close();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('INDI Control Panel')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _host,
                  decoration: const InputDecoration(labelText: 'Host'),
                ),
                TextField(
                  controller: _port,
                  decoration: InputDecoration(
                    labelText: 'Port',
                    helperText: kIsWeb
                        ? 'WebSocket bridge, e.g. websockify 8624 localhost:7624'
                        : null,
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _connecting ? null : _connect,
                  child: Text(_connecting ? 'Connecting…' : 'Connect'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Retries at once when the app returns to the foreground. The system cuts
/// the connections of an app in the background, and without this the
/// client would wait out its reconnection backoff.
class _ReconnectOnResume extends StatefulWidget {
  const _ReconnectOnResume({required this.client, required this.child});

  final IndiClient client;
  final Widget child;

  @override
  State<_ReconnectOnResume> createState() => _ReconnectOnResumeState();
}

class _ReconnectOnResumeState extends State<_ReconnectOnResume> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: widget.client.reconnectNow);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
