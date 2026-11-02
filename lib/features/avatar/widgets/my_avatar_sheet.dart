import 'package:flutter/material.dart';

import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/avatar/data/selfie_avatar.dart';
import 'package:couple_app/features/avatar/models/avatar_config.dart';
import 'package:couple_app/features/avatar/screens/avatar_builder_screen.dart';
import 'package:couple_app/features/avatar/screens/avatar_scan_screen.dart';
import 'package:couple_app/features/avatar/widgets/avatar_view.dart';

/// What tapping my own avatar does.
///
/// No avatar yet: straight to the live selfie scan, then the builder to
/// fine-tune and save what it made. With an avatar: a sheet to retake the
/// selfie (rebuilds the avatar from a new scan) or edit it by hand.
Future<void> openMyAvatar(BuildContext context, AppUser me) async {
  final avatar = me.avatar;
  if (avatar == null) {
    await _scanThenEdit(context, base: const AvatarConfig());
    return;
  }
  final choice = await showModalBottomSheet<_Choice>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => _MyAvatarSheet(me: me, avatar: avatar),
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case _Choice.scan:
      await _scanThenEdit(context, base: avatar);
    case _Choice.edit:
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const AvatarBuilderScreen()),
      );
  }
}

Future<void> _scanThenEdit(
  BuildContext context, {
  required AvatarConfig base,
}) async {
  final SelfieAvatar? scan = await AvatarScanScreen.open(context, base: base);
  if (scan == null || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => AvatarBuilderScreen(initial: scan)),
  );
}

enum _Choice { scan, edit }

class _MyAvatarSheet extends StatelessWidget {
  const _MyAvatarSheet({required this.me, required this.avatar});

  final AppUser me;
  final AvatarConfig avatar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                AvatarView(
                  config: avatar,
                  expression: AvatarExpression.happy,
                  size: 84,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        me.displayName,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Your avatar shows up when you send love.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, _Choice.scan),
              icon: const Icon(Icons.photo_camera_front_outlined),
              label: const Text('Retake selfie & rebuild avatar'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, _Choice.edit),
              icon: const Icon(Icons.brush_outlined),
              label: const Text('Edit avatar'),
            ),
          ],
        ),
      ),
    );
  }
}
