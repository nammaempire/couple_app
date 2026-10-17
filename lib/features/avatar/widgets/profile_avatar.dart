import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/avatar/widgets/avatar_view.dart';

/// A person's profile picture: their cartoon avatar when they chose to show
/// it, otherwise their photo, otherwise their initial.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.user,
    this.size = 48,
    this.fallbackName,
  });

  /// Null while the profile is loading or for someone not yet joined.
  final AppUser? user;
  final double size;

  /// Used for the initial when there is no photo; defaults to the user's
  /// display name.
  final String? fallbackName;

  @override
  Widget build(BuildContext context) {
    final u = user;
    final avatar = u?.avatar;
    if (u != null && avatar != null && u.showsAvatar) {
      return AvatarView(config: avatar, size: size);
    }

    final theme = Theme.of(context);
    final url = u?.photoUrl;
    final name = (fallbackName ?? u?.displayName ?? '').trim();
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();

    return CircleAvatar(
      radius: size / 2,
      backgroundColor: theme.colorScheme.primaryContainer,
      backgroundImage: url == null ? null : CachedNetworkImageProvider(url),
      child: url == null
          ? Text(
              initial,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
                fontSize: size * .38,
              ),
            )
          : null,
    );
  }
}
