import 'package:flutter/material.dart';

/// Prompts for a short name. Returns the new value, or null if cancelled.
///
/// When [allowEmpty] is true an empty result is a deliberate "clear it",
/// which callers use to fall back to a default name.
Future<String?> showNameEditDialog({
  required BuildContext context,
  required String title,
  required String label,
  String? initialValue,
  String? helperText,
  bool allowEmpty = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => _NameEditDialog(
      title: title,
      label: label,
      initialValue: initialValue,
      helperText: helperText,
      allowEmpty: allowEmpty,
    ),
  );
}

/// Stateful so the controller is disposed with the element, after the route's
/// exit animation. Disposing it when the future completes would tear the
/// controller down while the field is still mounted and listening.
class _NameEditDialog extends StatefulWidget {
  const _NameEditDialog({
    required this.title,
    required this.label,
    required this.initialValue,
    required this.helperText,
    required this.allowEmpty,
  });

  final String title;
  final String label;
  final String? initialValue;
  final String? helperText;
  final bool allowEmpty;

  @override
  State<_NameEditDialog> createState() => _NameEditDialogState();
}

class _NameEditDialogState extends State<_NameEditDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final value = _controller.text.trim();
    if (value.isEmpty && !widget.allowEmpty) return;
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final hasExistingValue = (widget.initialValue ?? '').isNotEmpty;

    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 24,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: widget.label,
          helperText: widget.helperText,
          helperMaxLines: 2,
          counterText: '',
        ),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (widget.allowEmpty && hasExistingValue)
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('Clear'),
          ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
