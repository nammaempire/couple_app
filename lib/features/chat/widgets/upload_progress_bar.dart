import 'package:flutter/material.dart';

/// Progress strip shown above the composer while media is uploading.
///
/// A null [progress] shows an indeterminate bar and just the [label].
class UploadProgressBar extends StatelessWidget {
  const UploadProgressBar({
    super.key,
    required this.label,
    required this.progress,
  });

  final String label;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        LinearProgressIndicator(value: progress),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            progress == null ? label : '$label ${(progress! * 100).round()}%',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
