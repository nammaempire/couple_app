import 'package:flutter/material.dart';

import 'package:couple_app/features/together/models/love_note.dart';

/// One action chip per "Open when…" template.
class OpenWhenTemplateRow extends StatelessWidget {
  const OpenWhenTemplateRow({super.key, required this.onTemplate});

  final ValueChanged<OpenWhen> onTemplate;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final t in OpenWhen.values)
          ActionChip(
            avatar: Text(t.emoji),
            label: Text(t.label),
            onPressed: () => onTemplate(t),
          ),
      ],
    );
  }
}
