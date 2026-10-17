import 'package:flutter/material.dart';

import 'package:couple_app/features/together/models/love_note.dart';

/// Sealed "Open when…" envelopes, two per row.
class OpenWhenEnvelopeGrid extends StatelessWidget {
  const OpenWhenEnvelopeGrid({
    super.key,
    required this.notes,
    required this.onOpen,
  });

  final List<LoveNote> notes;
  final ValueChanged<LoveNote> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.25,
      children: [
        for (final n in notes)
          Material(
            color: n.isOpened
                ? scheme.surfaceContainerHighest.withValues(alpha: .5)
                : scheme.primaryContainer,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              onTap: () => onOpen(n),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(n.emoji, style: const TextStyle(fontSize: 26)),
                        const Spacer(),
                        Icon(
                          n.isOpened ? Icons.drafts_outlined : Icons.mail,
                          size: 18,
                          color: scheme.primary,
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      n.envelopeTitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
