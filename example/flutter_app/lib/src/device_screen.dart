import 'package:flutter/material.dart';
import 'package:indi/indi.dart';

import 'property_card.dart';

/// Shows the properties of a device, one tab per group.
class DeviceScreen extends StatelessWidget {
  const DeviceScreen({super.key, required this.device});

  final IndiDevice device;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<IndiEvent>(
      // Properties are defined and deleted as the driver changes state,
      // for example after connecting.
      stream: device.events.where(
        (event) => event is PropertyDefined || event is PropertyRemoved,
      ),
      builder: (context, _) {
        final groups = device.groups;
        return DefaultTabController(
          key: ValueKey(groups.join('|')),
          length: groups.length,
          child: Scaffold(
            appBar: AppBar(
              title: Text(device.name),
              bottom: groups.isEmpty
                  ? null
                  : TabBar(
                      isScrollable: true,
                      tabs: [for (final group in groups) Tab(text: group)],
                    ),
            ),
            body: groups.isEmpty
                ? const Center(child: Text('No properties'))
                : TabBarView(
                    children: [
                      for (final group in groups)
                        ListView(
                          padding: const EdgeInsets.all(8),
                          children: [
                            for (final property in device.propertiesIn(group))
                              PropertyCard(
                                key: ValueKey(property.name),
                                device: device,
                                name: property.name,
                              ),
                          ],
                        ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}
