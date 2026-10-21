import 'package:flutter/material.dart';

import 'package:couple_app/features/together/models/love_note.dart';
import 'package:couple_app/features/together/widgets/note_theme.dart';

/// One chip per "Open when…" template, outlined in that envelope's
/// gradient.
class OpenWhenTemplateRow extends StatelessWidget {
  const OpenWhenTemplateRow({super.key, required this.onTemplate});

  final ValueChanged<OpenWhen> onTemplate;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 10,
      children: [
        for (final t in OpenWhen.values)
          _GradientChip(template: t, onTap: () => onTemplate(t)),
      ],
    );
  }
}

class _GradientChip extends StatelessWidget {
  const _GradientChip({required this.template, required this.onTap});

  final OpenWhen template;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    final preset = NoteTheme.forOpenWhen(template).preset;
    final ring = preset.alwaysDark
        ? const [Color(0xFF3D3A8C), Color(0xFF8E7CFF), Color(0xFFFFD36E)]
        : [
            for (final c in preset.colors(Brightness.light))
              Color.lerp(c, preset.accent(Brightness.light), .45)!,
          ];
    final radius = BorderRadius.circular(24);
    return Semantics(
      button: true,
      child: Container(
        padding: const EdgeInsets.all(1.6),
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(colors: ring),
        ),
        child: Material(
          color: Color.alphaBlend(
            ring[1].withValues(alpha: b == Brightness.dark ? .14 : .1),
            theme.colorScheme.surface,
          ),
          borderRadius: BorderRadius.circular(22.4),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(22.4),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(template.emoji, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      template.label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
