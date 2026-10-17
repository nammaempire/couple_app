import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/avatar/models/avatar_config.dart';
import 'package:couple_app/features/avatar/widgets/avatar_view.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';

/// The partner's face on the call screens: their cartoon avatar when they
/// show it as their profile picture ([AppUser.showsAvatar]), otherwise a
/// translucent rose circle with the first letter of [name]. While their
/// profile loads, the initial shows.
class PartnerInitialAvatar extends ConsumerWidget {
  const PartnerInitialAvatar({
    super.key,
    required this.name,
    required this.size,
    required this.fontSize,
  });

  final String name;
  final double size;
  final double fontSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partner = ref.watch(partnerProvider).value;
    final avatar = partner?.avatar;
    if (partner != null && avatar != null && partner.showsAvatar) {
      return AvatarView(
        config: avatar,
        expression: AvatarExpression.happy,
        size: size,
      );
    }

    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFE05C7B).withValues(alpha: .25),
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
