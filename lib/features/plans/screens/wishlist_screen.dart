import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/core/widgets/empty_state.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/plans/data/wishlist_service.dart';
import 'package:couple_app/features/plans/models/wishlist_claim.dart';
import 'package:couple_app/features/plans/models/wishlist_item.dart';
import 'package:couple_app/features/plans/providers/wishlist_providers.dart';
import 'package:couple_app/features/plans/screens/wishlist_item_editor_screen.dart';
import 'package:couple_app/features/plans/widgets/wishlist_item_card.dart';
import 'package:couple_app/features/plans/widgets/wishlist_partner_item_card.dart';
import 'package:couple_app/features/plans/widgets/wishlist_secret_banner.dart';

/// Two wishlists side by side: yours, and your partner's, where you can
/// secretly claim something to get them.
class WishlistScreen extends ConsumerStatefulWidget {
  const WishlistScreen({super.key});

  @override
  ConsumerState<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends ConsumerState<WishlistScreen>
    with SingleTickerProviderStateMixin {
  late final String _coupleId;
  late final String _myUid;
  late final WishlistService _service;
  late final TabController _tabs = TabController(length: 2, vsync: this);

  /// Items with a claim change in flight.
  final _busy = <String>{};

  @override
  void initState() {
    super.initState();
    _coupleId = ref.read(currentCoupleIdProvider);
    _myUid = ref.read(currentUidProvider);
    _service = ref.read(wishlistServiceProvider);
    // The add button only belongs on "My wishes".
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _openEditor([WishlistItem? item]) {
    Navigator.of(context).push(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => WishlistItemEditorScreen(item: item),
      ),
    );
  }

  Future<void> _openLink(String url) async {
    try {
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) context.showSnackMessage('Could not open the link.');
    } catch (_) {
      if (mounted) context.showSnackMessage('Could not open the link.');
    }
  }

  Future<void> _onOwnAction(WishlistItem item, WishlistOwnAction action) async {
    switch (action) {
      case WishlistOwnAction.edit:
        _openEditor(item);
      case WishlistOwnAction.openLink:
        await _openLink(item.url);
      case WishlistOwnAction.toggleReceived:
        try {
          await _service.setReceived(
            coupleId: _coupleId,
            itemId: item.id,
            received: !item.received,
          );
        } catch (_) {
          if (mounted) {
            context.showSnackMessage(
              'Could not update. Check your connection.',
            );
          }
        }
      case WishlistOwnAction.delete:
        await _delete(item);
    }
  }

  Future<void> _delete(WishlistItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this wish?'),
        content: const Text('This removes it for both of you.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.delete(_coupleId, item.id);
    } catch (_) {
      if (mounted) {
        context.showSnackMessage('Could not delete. Check your connection.');
      }
    }
  }

  Future<void> _onClaimAction(
    WishlistItem item,
    WishlistClaimAction action,
  ) async {
    if (_busy.contains(item.id)) return;
    setState(() => _busy.add(item.id));
    try {
      switch (action) {
        case WishlistClaimAction.claim:
          await _service.claim(coupleId: _coupleId, item: item, myUid: _myUid);
        case WishlistClaimAction.markBought:
          await _service.markPurchased(
            coupleId: _coupleId,
            itemId: item.id,
            purchased: true,
          );
        case WishlistClaimAction.markNotBought:
          await _service.markPurchased(
            coupleId: _coupleId,
            itemId: item.id,
            purchased: false,
          );
        case WishlistClaimAction.unclaim:
          await _service.unclaim(coupleId: _coupleId, itemId: item.id);
      }
    } catch (_) {
      if (mounted) {
        context.showSnackMessage('Could not update. Check your connection.');
      }
    } finally {
      if (mounted) setState(() => _busy.remove(item.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(wishlistItemsProvider);
    final partnerName = ref.watch(partnerNameProvider);
    final couple = ref.watch(coupleProvider).value;
    final currency = couple?.currency ?? Couple.defaultCurrency;
    final hasPartner = couple?.partnerIdFor(_myUid) != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wishlist'),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            const Tab(text: 'My wishes'),
            Tab(
              child: Text(
                '$partnerName\'s wishes',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _tabs.index == 0
          ? FloatingActionButton.extended(
              heroTag: 'add-wishlist-item',
              onPressed: _openEditor,
              icon: const Icon(Icons.add),
              label: const Text('Add a wish'),
            )
          : null,
      body: !items.hasValue && !items.hasError
          ? const Center(child: CircularProgressIndicator())
          : !items.hasValue
          ? const EmptyState(
              icon: Icons.cloud_off,
              text: 'Could not load the wishlist.',
            )
          : TabBarView(
              controller: _tabs,
              children: [
                _myWishes(items.value!, partnerName, currency),
                _partnerWishes(items.value!, partnerName, currency, hasPartner),
              ],
            ),
    );
  }

  Widget _myWishes(
    List<WishlistItem> all,
    String partnerName,
    String currency,
  ) {
    final mine = WishlistItem.sorted(all.where((i) => i.createdBy == _myUid));
    if (mine.isEmpty) {
      return EmptyState(
        icon: Icons.card_giftcard,
        text:
            'Nothing on your wishlist yet.\n'
            'Add things you\'d love, so $partnerName always has ideas.',
        padding: const EdgeInsets.all(32),
      );
    }
    final wanted = mine.where((i) => !i.received).toList();
    final received = mine.where((i) => i.received).toList();

    Widget card(WishlistItem item) => WishlistItemCard(
      key: ValueKey(item.id),
      item: item,
      currency: currency,
      onAction: (a) => _onOwnAction(item, a),
    );

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 96),
      children: [
        ...wanted.map(card),
        if (received.isNotEmpty) ...[
          const _SectionTitle('Received'),
          ...received.map(card),
        ],
      ],
    );
  }

  Widget _partnerWishes(
    List<WishlistItem> all,
    String partnerName,
    String currency,
    bool hasPartner,
  ) {
    final theirs = WishlistItem.sorted(
      all.where((i) => i.createdBy.isNotEmpty && i.createdBy != _myUid),
    );
    if (theirs.isEmpty) {
      return EmptyState(
        icon: Icons.redeem_outlined,
        text: hasPartner
            ? '$partnerName hasn\'t added any wishes yet.\n'
                  'Maybe drop a hint?'
            : 'Once your partner joins, their wishes will show up here.',
        padding: const EdgeInsets.all(32),
      );
    }

    final claims = ref.watch(myWishlistClaimsProvider);
    final myClaims = claims.value ?? const <String, WishlistClaim>{};
    final wanted = theirs.where((i) => !i.received).toList();
    final received = theirs.where((i) => i.received).toList();

    Widget card(WishlistItem item) => WishlistPartnerItemCard(
      key: ValueKey(item.id),
      item: item,
      claim: myClaims[item.id],
      partnerName: partnerName,
      currency: currency,
      busy: _busy.contains(item.id),
      // If my claims failed to load, still allow claiming; the service
      // treats a claim that already exists as done.
      canClaim: claims.hasValue || claims.hasError,
      onAction: (a) => _onClaimAction(item, a),
      onOpenLink: () => _openLink(item.url),
    );

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        WishlistSecretBanner(partnerName: partnerName),
        ...wanted.map(card),
        if (received.isNotEmpty) ...[
          _SectionTitle('$partnerName already has'),
          ...received.map(card),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
      child: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
