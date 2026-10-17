import 'package:flutter/material.dart';

import 'package:couple_app/features/onboarding/widgets/check_bullet.dart';

/// Plain-language explanation of what a couple connection means.
class HowConnectingWorks extends StatelessWidget {
  const HowConnectingWorks({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        leading: Icon(Icons.info_outline, color: theme.colorScheme.primary),
        title: Text('How connecting works', style: theme.textTheme.titleSmall),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: const [
          CheckBullet('A space is made for exactly two people.'),
          CheckBullet('You can be connected to one partner at a time.'),
          CheckBullet(
            'Each invite code works once. After your partner joins, it '
            'stops working.',
          ),
          CheckBullet(
            'Chats, photos, moods and answers are visible only to the '
            'two of you.',
          ),
        ],
      ),
    );
  }
}
