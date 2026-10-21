import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/plans/models/wishlist_item.dart';
import 'package:couple_app/features/plans/widgets/soft_kit.dart';
import 'package:couple_app/features/plans/widgets/wishlist_item_meta.dart';

/// Actions on one of your own wishes.
enum WishlistOwnAction { edit, toggleReceived, openLink, delete }

/// One of your own wishes. Deliberately shows nothing about whether your
/// partner is getting it.
class WishlistItemCard extends StatelessWidget {
  const WishlistItemCard({
    super.key,
    required this.item,
    required this.currency,
    required this.onAction,
  });

  final WishlistItem item;
  final String currency;
  final ValueChanged<WishlistOwnAction> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return TintedCard(
      preset: WishlistLook.presetFor(item.priority),
      muted: item.received,
      onTap: () => onAction(WishlistOwnAction.edit),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    item.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: item.received ? scheme.onSurfaceVariant : null,
                    ),
                  ),
                ),
              ),
              if (item.hasLink)
                IconButton(
                  tooltip: 'Open link',
                  icon: const Icon(Icons.open_in_new),
                  onPressed: () => onAction(WishlistOwnAction.openLink),
                ),
              PopupMenuButton<WishlistOwnAction>(
                tooltip: 'More',
                onSelected: onAction,
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: WishlistOwnAction.edit,
                    child: Text('Edit'),
                  ),
                  PopupMenuItem(
                    value: WishlistOwnAction.toggleReceived,
                    child: Text(
                      item.received ? 'Not received yet' : 'I got this',
                    ),
                  ),
                  const PopupMenuItem(
                    value: WishlistOwnAction.delete,
                    child: Text('Delete'),
                  ),
                ],
              ),
            ],
          ),
          if (item.notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12, bottom: 8),
              child: Text(
                item.notes,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: item.received
                ? Row(
                    children: [
                      Icon(Icons.check_circle, size: 18, color: scheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        'You got this',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  )
                : WishlistItemMeta(item: item, currency: currency),
          ),
        ],
      ),
    );
  }
}

/// The gradient each wish wears, by how much it's wanted.
abstract final class WishlistLook {
  static GradientPreset presetFor(WishlistPriority p) => switch (p) {
    WishlistPriority.love => GradientPreset.blush,
    WishlistPriority.like => GradientPreset.peach,
    WishlistPriority.someday => GradientPreset.lavender,
  };
}
