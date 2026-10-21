import 'package:flutter/material.dart';

import 'package:couple_app/features/chat/widgets/chat_chrome.dart';
import 'package:couple_app/features/chat/widgets/chat_palette.dart';

/// Floating progress pill shown above the composer while media is
/// uploading.
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
    final palette = ChatPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: ChatGlass(
        radius: 18,
        padding: const EdgeInsets.fromLTRB(12, 8, 14, 10),
        child: Row(
          children: [
            const GradientBadge(
              icon: Icons.cloud_upload_outlined,
              size: 30,
              iconSize: 16,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    progress == null
                        ? label
                        : '$label ${(progress! * 100).round()}%',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 5,
                      color: palette.accentGradient.last,
                      backgroundColor: theme.colorScheme.primary.withValues(
                        alpha: .14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
