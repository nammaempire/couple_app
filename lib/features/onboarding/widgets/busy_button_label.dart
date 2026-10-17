import 'package:flutter/material.dart';

/// Button label that turns into a small spinner while [busy].
class BusyButtonLabel extends StatelessWidget {
  const BusyButtonLabel({super.key, required this.busy, required this.label});

  final bool busy;
  final String label;

  @override
  Widget build(BuildContext context) => busy
      ? const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : Text(label);
}
