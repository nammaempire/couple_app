import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/avatar/models/avatar_config.dart';
import 'package:couple_app/features/avatar/widgets/profile_avatar.dart';
import 'package:couple_app/features/home/widgets/love_burst.dart';

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
    this.onTapMe,
  });

  final String greeting;
  final String subtitle;
  final String myName;
  final String partnerName;
  final AppUser? me;

  /// Null until the partner has joined and their profile has loaded.
  final AppUser? partner;
  final String? couplePhotoUrl;

  /// Tapping my own avatar (make or change it).
  final VoidCallback? onTapMe;

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
            onTapMe: onTapMe,
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
    this.onTapMe,
  });

  final String myName;
  final String partnerName;
  final AppUser? me;
  final AppUser? partner;
  final VoidCallback? onTapMe;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      height: 52,
      child: Stack(
        // Room for the bounce when a love tap lands.
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            child: _Avatar(
              name: myName,
              user: me,
              onTap: onTapMe,
              tooltip: 'Your avatar',
            ),
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

/// One partner's picture. While they've just sent or received a love tap,
/// their cartoon avatar pulls that tap's face and gives a little bounce.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.user, this.onTap, this.tooltip});

  final String name;
  final AppUser? user;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final uid = user?.uid;
    Widget avatar = ValueListenableBuilder<Map<String, AvatarExpression>>(
      valueListenable: AvatarReactions.faces,
      builder: (context, faces, _) {
        final face = uid == null ? null : faces[uid];
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 1, end: face == null ? 1 : 1.18),
          duration: const Duration(milliseconds: 260),
          curve: face == null ? Curves.easeOut : Curves.elasticOut,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: Container(
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).scaffoldBackgroundColor,
            ),
            child: ProfileAvatar(
              user: user,
              size: 47,
              fallbackName: name,
              expression: face ?? AvatarExpression.neutral,
            ),
          ),
        );
      },
    );
    final tap = onTap;
    if (tap != null) {
      avatar = Tooltip(
        message: tooltip ?? name,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: tap,
          child: avatar,
        ),
      );
    }
    return avatar;
  }
}
