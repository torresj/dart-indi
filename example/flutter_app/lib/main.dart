import 'package:flutter/material.dart';

import 'src/connect_screen.dart';

void main() => runApp(const IndiExampleApp());

/// An INDI control panel: connect to a server, browse its devices and
/// change their properties.
class IndiExampleApp extends StatelessWidget {
  const IndiExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'INDI Control Panel',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      home: const ConnectScreen(),
    );
  }
}
