import 'package:flutter/material.dart';
import 'package:indi/indi.dart';

/// The color INDI clients traditionally use for each state.
Color stateColor(PropertyState state) => switch (state) {
      PropertyState.idle => Colors.grey,
      PropertyState.ok => Colors.green,
      PropertyState.busy => Colors.amber,
      PropertyState.alert => Colors.red,
    };

/// A small colored dot showing [state].
class StateDot extends StatelessWidget {
  const StateDot(this.state, {super.key});

  final PropertyState state;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: state.wireValue,
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: stateColor(state),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
