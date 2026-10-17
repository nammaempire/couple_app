import 'package:flutter/material.dart';

import 'package:couple_app/features/plans/models/bucket_progress.dart';

/// A soft card with "12 of 40 done" and a progress bar.
class BucketProgressHeader extends StatelessWidget {
  const BucketProgressHeader({
    super.key,
    required this.progress,
    this.categoryLabel,
  });

  final BucketProgress progress;

  /// The category being filtered on, if any.
  final String? categoryLabel;

  String get _caption {
    if (progress.total == 0) return 'Nothing here yet';
    if (progress.isComplete) return 'Every single one. You two are amazing.';
    if (progress.done == 0) return 'Your adventures are waiting';
    if (progress.remaining == 1) return 'Just one more to go';
    return '${progress.remaining} still to go';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      elevation: 0,
      color: scheme.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (categoryLabel != null)
                        Text(
                          categoryLabel!,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: scheme.onPrimaryContainer.withValues(
                              alpha: 0.8,
                            ),
                          ),
                        ),
                      Text(
                        progress.label,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${progress.percent}%',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TweenAnimationBuilder<double>(
              tween: Tween(end: progress.fraction),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 10,
                  backgroundColor: scheme.surface.withValues(alpha: 0.6),
                  color: scheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _caption,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
