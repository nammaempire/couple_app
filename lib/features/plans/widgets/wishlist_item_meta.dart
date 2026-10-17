import 'package:flutter/material.dart';

import 'package:couple_app/features/plans/models/wishlist_item.dart';
import 'package:couple_app/features/plans/models/wishlist_price.dart';

/// Small chips under a wish: priority, occasion and price.
class WishlistItemMeta extends StatelessWidget {
  const WishlistItemMeta({
    super.key,
    required this.item,
    required this.currency,
  });

  final WishlistItem item;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget pill(String text, {bool strong = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: strong ? scheme.secondaryContainer : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          color: strong ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
          fontWeight: strong ? FontWeight.w600 : null,
        ),
      ),
    );

    final price = item.priceMinor;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        pill(
          '${item.priority.emoji} ${item.priority.label}',
          strong: item.priority == WishlistPriority.love,
        ),
        if (item.occasion != WishlistOccasion.any)
          pill('${item.occasion.emoji} ${item.occasion.label}'),
        if (price != null)
          pill(
            price == 0 ? 'Free' : WishlistPrice.format(price, currency),
            strong: true,
          ),
      ],
    );
  }
}
