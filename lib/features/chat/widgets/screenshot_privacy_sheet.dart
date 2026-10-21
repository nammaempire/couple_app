import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/chat/providers/chat_providers.dart';
import 'package:couple_app/features/chat/widgets/chat_chrome.dart';

/// Bottom sheet from the chat menu with the shared "block screenshots of
/// our chat" switch, and what screenshot alerts can and can't do.
///
/// The switch reflects the couple document live, so it also moves when the
/// partner flips it.
class ScreenshotPrivacySheet extends ConsumerWidget {
  const ScreenshotPrivacySheet({
    super.key,
    required this.partnerName,
    required this.onChanged,
  });

  final String partnerName;

  /// Called with the new value when the switch is flipped.
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final blocked = ref.watch(blockScreenshotsProvider);

    return SafeArea(
      // Scrolls rather than overflowing with large text.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ChatSheetHeader(
              title: 'Screenshots',
              icon: Icons.screenshot_outlined,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Material(
                color: theme.brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: .06)
                    : Colors.white.withValues(alpha: .72),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: Colors.white.withValues(
                      alpha: theme.brightness == Brightness.dark ? .08 : .9,
                    ),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: SwitchListTile(
                  contentPadding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                  secondary: const GradientBadge(
                    icon: Icons.screenshot_monitor_outlined,
                    size: 38,
                    iconSize: 20,
                  ),
                  title: Text(
                    'Block screenshots of our chat',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    'On both phones, screenshots and screen recordings of the '
                    'chat come out black, and it is hidden in recent apps. '
                    '$partnerName will see that you changed this.',
                  ),
                  value: blocked,
                  onChanged: onChanged,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 14, 28, 24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'When blocking is off, a screenshot of the chat tells the '
                      'other person. Only Android 14 and newer can detect '
                      'screenshots, so on older phones blocking is the sure '
                      'way to keep the chat private.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
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
