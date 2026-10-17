import 'package:flutter/material.dart';

/// Centered error message for a pairing step; empty when [error] is null.
class PairingErrorText extends StatelessWidget {
  const PairingErrorText({super.key, required this.error});

  final String? error;

  @override
  Widget build(BuildContext context) {
    if (error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Text(
        error!,
        textAlign: TextAlign.center,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}
