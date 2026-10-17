import 'package:flutter/material.dart';

/// The dark rose gradient behind the call screens.
class CallBackdrop extends StatelessWidget {
  const CallBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF3B2229), Color(0xFF14100F)],
        ),
      ),
      child: child,
    );
  }
}
