import 'package:flutter/material.dart';

/// A tappable read-only field that opens a date or time picker.
class EventPickerField extends StatelessWidget {
  const EventPickerField({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
    required this.onTap,
    this.trailing,
  });

  final String label;
  final IconData icon;
  final String value;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          suffixIcon: trailing,
        ),
        child: Text(value),
      ),
    );
  }
}
