import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/avatar/widgets/profile_avatar.dart';

/// Top of Home: greeting plus the couple photo, or both partners' avatars
/// side by side when no couple photo is set. Each partner shows as their
/// cartoon avatar, photo or initial (see [ProfileAvatar]).
class CoupleHeader extends StatelessWidget {
  const CoupleHeader({
    super.key,
    required this.greeting,
    required this.subtitle,
    required this.myName,
    required this.partnerName,
    this.me,
    this.partner,
    this.couplePhotoUrl,
  });

  final String greeting;
  final String subtitle;
  final String myName;
  final String partnerName;
  final AppUser? me;

  /// Null until the partner has joined and their profile has loaded.
  final AppUser? partner;
  final String? couplePhotoUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final couplePhoto = couplePhotoUrl;

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          greeting,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: couplePhoto == null ? null : Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: couplePhoto == null
                ? theme.colorScheme.onSurfaceVariant
                : Colors.white.withValues(alpha: .85),
          ),
        ),
      ],
    );

    if (couplePhoto == null) {
      return Row(
        children: [
          Expanded(child: text),
          const SizedBox(width: 12),
          _AvatarPair(
            myName: myName,
            partnerName: partnerName,
            me: me,
            partner: partner,
          ),
        ],
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: 168,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: couplePhoto,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) =>
                  Container(color: theme.colorScheme.primary),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xB3000000)],
                  stops: [.35, 1],
                ),
              ),
            ),
            Positioned(left: 20, right: 20, bottom: 16, child: text),
          ],
        ),
      ),
    );
  }
}

class _AvatarPair extends StatelessWidget {
  const _AvatarPair({
    required this.myName,
    required this.partnerName,
    this.me,
    this.partner,
  });

  final String myName;
  final String partnerName;
  final AppUser? me;
  final AppUser? partner;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      height: 52,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            child: _Avatar(name: myName, user: me),
          ),
          Positioned(
            right: 0,
            child: _Avatar(name: partnerName, user: partner),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.user});

  final String name;
  final AppUser? user;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).scaffoldBackgroundColor,
      ),
      child: ProfileAvatar(user: user, size: 47, fallbackName: name),
    );
  }
}
