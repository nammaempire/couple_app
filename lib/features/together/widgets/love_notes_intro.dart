import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/floating_hearts.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/together/models/love_note.dart';
import 'package:couple_app/features/together/widgets/note_theme.dart';
import 'package:couple_app/features/together/widgets/open_when_template_row.dart';

/// The drifting blush card at the top of Love notes: a headline, a line
/// under it and a "Write a note" button, with hearts floating behind.
class LoveNotesHero extends StatelessWidget {
  const LoveNotesHero({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onWrite,
  });

  final String title;
  final String subtitle;
  final VoidCallback onWrite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    const preset = GradientPreset.blush;
    return AnimatedGradientCard(
      preset: preset,
      radius: 28,
      padding: EdgeInsets.zero,
      child: Stack(
        children: [
          Positioned.fill(
            child: FloatingHearts(
              count: 10,
              color: Colors.white,
              opacity: b == Brightness.dark ? .25 : .7,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: noteSerif(theme.textTheme.headlineSmall)
                            .copyWith(
                              color: preset.foreground(b),
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text('💌', style: TextStyle(fontSize: 40)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: preset.foregroundMuted(b),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onWrite,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 46),
                    backgroundColor: b == Brightness.dark
                        ? preset.accent(b)
                        : preset.ink,
                    foregroundColor: b == Brightness.dark
                        ? const Color(0xFF3B1424)
                        : Colors.white,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Write a note'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Welcome card shown before any notes exist, with "Open when…" templates.
class LoveNotesIntro extends StatelessWidget {
  const LoveNotesIntro({
    super.key,
    required this.partnerName,
    required this.onTemplate,
    this.onWrite,
  });

  final String partnerName;
  final ValueChanged<OpenWhen> onTemplate;
  final VoidCallback? onWrite;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LoveNotesHero(
          title: 'Leave $partnerName a love note',
          subtitle:
              'Send it now, schedule it for a special day, or leave an '
              '“Open when…” envelope for when they need it. Scheduled '
              'notes stay sealed until they arrive.',
          onWrite: onWrite ?? () {},
        ),
        const SizedBox(height: 16),
        OpenWhenTemplateRow(onTemplate: onTemplate),
      ],
    );
  }
}
