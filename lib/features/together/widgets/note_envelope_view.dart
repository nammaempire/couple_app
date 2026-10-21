import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/entrance_animation.dart';
import 'package:couple_app/features/together/models/love_note.dart';
import 'package:couple_app/features/together/widgets/envelope_art.dart';
import 'package:couple_app/features/together/widgets/note_theme.dart';

/// A delivered "Open when…" envelope waiting to be opened. Drawn over the
/// note's gradient (the reader paints the background).
class NoteEnvelopeView extends StatelessWidget {
  const NoteEnvelopeView({
    super.key,
    required this.note,
    required this.onOpen,
    this.from,
    this.opening = false,
  });

  final LoveNote note;
  final VoidCallback onOpen;

  /// The sender's name, shown above the envelope.
  final String? from;

  /// The words are being fetched.
  final bool opening;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    final look = NoteTheme.of(note);
    final fg = look.preset.foreground(b);
    final muted = look.preset.foregroundMuted(b);
    final accent = look.preset.ink;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: opening ? null : onOpen,
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight - 48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (from != null)
                  Text(
                    'FROM ${from!.toUpperCase()}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: muted,
                      letterSpacing: 2.4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                const SizedBox(height: 36),
                Bobbing(
                  amplitude: 7,
                  tilt: .015,
                  child: EnvelopeArt(
                    preset: look.preset,
                    width: 264,
                    seal: WaxSeal(preset: look.preset, label: note.emoji),
                  ),
                ),
                const SizedBox(height: 44),
                Text(
                  note.envelopeTitle,
                  textAlign: TextAlign.center,
                  style: noteSerif(theme.textTheme.headlineSmall).copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Only open it when the moment is right.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: opening ? null : onOpen,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(200, 54),
                    backgroundColor: Colors.white,
                    foregroundColor: accent,
                    disabledBackgroundColor: Colors.white.withValues(alpha: .7),
                    elevation: 2,
                    shadowColor: accent.withValues(alpha: .4),
                    shape: const StadiumBorder(),
                    textStyle: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  icon: opening
                      ? SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: accent,
                          ),
                        )
                      : const Icon(Icons.drafts_outlined),
                  label: const Text('Open it'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
