import 'package:flutter/material.dart';

extension SnackBarMessages on BuildContext {
  /// Shows [message] in a snack bar. Does nothing if this context is no
  /// longer mounted, so it is safe to call after an `await`.
  void showSnackMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(this).showSnackBar(SnackBar(content: Text(message)));
  }
}
