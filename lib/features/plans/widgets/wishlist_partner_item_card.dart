import 'package:flutter/material.dart';

import 'package:couple_app/features/plans/models/wishlist_claim.dart';
import 'package:couple_app/features/plans/models/wishlist_item.dart';
import 'package:couple_app/features/plans/widgets/wishlist_item_meta.dart';

/// What you can do with one of your partner's wishes.
enum WishlistClaimAction { claim, markBought, markNotBought, unclaim }

/// One of your partner's wishes, with your secret "I'll get this" state.
class WishlistPartnerItemCard extends StatelessWidget {
  const WishlistPartnerItemCard({
    super.key,
    required this.item,
    required this.claim,
    required this.partnerName,
    required this.currency,
    required this.busy,
    required this.canClaim,
    required this.onAction,
    required this.onOpenLink,
  });

  final WishlistItem item;

  /// My claim on it, if any. Never anyone else's.
  final WishlistClaim? claim;
  final String partnerName;
  final String currency;

  /// A claim change is in flight.
  final bool busy;

  /// False until my claims have loaded, so a claim is never doubled.
  final bool canClaim;
  final ValueChanged<WishlistClaimAction> onAction;
  final VoidCallback onOpenLink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final claim = this.claim;
    final mine = claim != null;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      elevation: 0,
      color: mine
          ? scheme.tertiaryContainer.withValues(alpha: 0.55)
          : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
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
                      ),
                    ),
                  ),
                ),
                if (item.hasLink)
                  IconButton(
                    tooltip: 'Open link',
                    icon: const Icon(Icons.open_in_new),
                    onPressed: onOpenLink,
                  ),
              ],
            ),
            if (item.notes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 8),
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
              padding: const EdgeInsets.only(right: 8),
              child: WishlistItemMeta(item: item, currency: currency),
            ),
            const SizedBox(height: 12),
            _claimArea(context, claim),
          ],
        ),
      ),
    );
  }

  Widget _claimArea(BuildContext context, WishlistClaim? claim) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (item.received && claim == null) {
      return Row(
        children: [
          Icon(Icons.check_circle_outline, size: 18, color: scheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '$partnerName already has this',
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
    }

    final secretNote = Row(
      children: [
        Icon(Icons.lock_outline, size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            '$partnerName won\'t see this',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );

    if (claim == null) {
      return Row(
        children: [
          Expanded(child: secretNote),
          FilledButton.tonalIcon(
            onPressed: busy || !canClaim
                ? null
                : () => onAction(WishlistClaimAction.claim),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            icon: const Icon(Icons.card_giftcard, size: 18),
            label: const Text('I\'ll get this'),
          ),
        ],
      );
    }

    final status = claim.purchased
        ? 'Bought. Your secret is safe.'
        : 'You\'re getting this';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              claim.purchased ? Icons.redeem : Icons.lock,
              size: 18,
              color: scheme.tertiary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                status,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.onTertiaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        secretNote,
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            if (claim.purchased)
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () => onAction(WishlistClaimAction.markNotBought),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                child: const Text('Not bought yet'),
              )
            else
              FilledButton.icon(
                onPressed: busy
                    ? null
                    : () => onAction(WishlistClaimAction.markBought),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                icon: const Icon(Icons.shopping_bag_outlined, size: 18),
                label: const Text('Bought it'),
              ),
            TextButton(
              onPressed: busy
                  ? null
                  : () => onAction(WishlistClaimAction.unclaim),
              style: TextButton.styleFrom(minimumSize: const Size(0, 40)),
              child: const Text('Unclaim'),
            ),
          ],
        ),
      ],
    );
  }
}
