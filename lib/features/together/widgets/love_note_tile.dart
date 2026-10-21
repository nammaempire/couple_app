import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/entrance_animation.dart';
import 'package:couple_app/features/together/models/love_note.dart';
import 'package:couple_app/features/together/widgets/envelope_art.dart';
import 'package:couple_app/features/together/widgets/note_theme.dart';

/// A love note in a list: a seal with its emoji (or a lock while sealed),
/// title and status, on the note's gradient. Unread notes glow and pulse;
/// [muted] notes (sent by you) sit quietly on the surface.
class LoveNoteTile extends StatelessWidget {
  const LoveNoteTile({
    super.key,
    required this.note,
    required this.subtitle,
    required this.onTap,
    this.sealed = false,
    this.unread = false,
    this.muted = false,
    this.countdown,
  });

  final LoveNote note;
  final String subtitle;
  final VoidCallback onTap;
  final bool sealed;
  final bool unread;
  final bool muted;

  /// A short time-left label for sealed notes, e.g. "2d 14h".
  final String? countdown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final b = theme.brightness;
    final look = NoteTheme.of(note);
    final preset = look.preset;
    final fg = muted ? scheme.onSurface : preset.foreground(b);
    final fgMuted = muted ? scheme.onSurfaceVariant : preset.foregroundMuted(b);
    final accent = muted ? scheme.primary : preset.accent(b);

    final seal = sealed
        ? Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(
                alpha: preset.isDarkIn(b) ? .16 : .6,
              ),
            ),
            child: Icon(Icons.lock_rounded, color: accent, size: 22),
          )
        : muted
        ? Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.primaryContainer.withValues(alpha: .6),
            ),
            child: Text(note.emoji, style: const TextStyle(fontSize: 22)),
          )
        : WaxSeal(preset: preset, label: note.emoji, size: 46);

    final row = Row(
      children: [
        seal,
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                note.envelopeTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: noteSerif(theme.textTheme.titleMedium).copyWith(
                  color: fg,
                  fontWeight: unread ? FontWeight.w800 : FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(color: fgMuted),
              ),
            ],
          ),
        ),
        if (note.hasVoice)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Icon(Icons.mic_none, size: 18, color: accent),
          ),
        if (countdown != null)
          Container(
            margin: const EdgeInsets.only(left: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(
                alpha: preset.isDarkIn(b) ? .14 : .65,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.hourglass_top_rounded, size: 13, color: accent),
                const SizedBox(width: 4),
                Text(
                  countdown!,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        if (unread)
          Pulse(
            builder: (context, v, _) => Container(
              margin: const EdgeInsets.only(left: 10),
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: .5),
                    blurRadius: 4 + 6 * v,
                    spreadRadius: 1 + 3 * v,
                  ),
                ],
              ),
            ),
          ),
      ],
    );

    if (muted) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: scheme.surfaceContainerHighest.withValues(alpha: .45),
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
              child: row,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedGradientCard(
        preset: preset,
        onTap: onTap,
        radius: 22,
        animate: unread || sealed,
        sheen: unread,
        glow: unread ? preset.accent(b) : null,
        padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
        child: row,
      ),
    );
  }
}
