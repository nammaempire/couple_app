import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/onboarding/widgets/busy_button_label.dart';
import 'package:couple_app/features/onboarding/widgets/romance_kit.dart';
import 'package:couple_app/features/premium/models/products.dart';
import 'package:couple_app/features/premium/providers/premium_providers.dart';
import 'package:couple_app/features/premium/widgets/purchase_status_banner.dart';

/// Choose a gift for your partner (months of Premium, or a Memory book),
/// write them a message, and buy it. They get a surprise to open.
///
/// While a Premium subscription is running, months of Premium aren't
/// offered (they could be partly lost when it renews); a book always is.
class GiftComposerScreen extends ConsumerStatefulWidget {
  const GiftComposerScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const GiftComposerScreen());

  static final productKey = Products.gifts.join(',');

  @override
  ConsumerState<GiftComposerScreen> createState() => _GiftComposerScreenState();
}

class _GiftComposerScreenState extends ConsumerState<GiftComposerScreen> {
  final _message = TextEditingController();
  String? _selected;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  void _send(String productId) {
    ref
        .read(purchaseControllerProvider.notifier)
        .buy(
          productId,
          coupleId: ref.read(currentCoupleIdProvider),
          giftMessage: _message.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final partner = ref.watch(partnerNameProvider);
    final me = ref.watch(currentUserProvider);
    final premium = ref.watch(premiumProvider);
    final now = ref.watch(premiumClockProvider)();
    final subscribed = premium?.hasActiveSubscription(now) ?? false;
    final products = ref.watch(
      storeProductsProvider(GiftComposerScreen.productKey),
    );
    final purchase = ref.watch(purchaseControllerProvider);

    final options = [
      if (!subscribed) ...[
        Products.giftPremium1m,
        Products.giftPremium3m,
        Products.giftPremium12m,
      ],
      Products.giftBook,
    ];
    final selected = options.contains(_selected) ? _selected! : options.last;
    final price = products.value?[selected]?.price;
    final what = Products.label(selected);

    return RomanceBackdrop(
      preset: GradientPreset.blush,
      strength: .5,
      hearts: true,
      heartCount: 8,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: romanceAppBar(
          automaticallyImplyLeading: true,
          title: const Text('Send a gift'),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              Center(
                child: GlowBadge(
                  preset: GradientPreset.festive,
                  icon: Icons.card_giftcard_rounded,
                  size: 68,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'A surprise for $partner',
                textAlign: TextAlign.center,
                style: romanceSerif(theme.textTheme.headlineSmall).copyWith(
                  fontWeight: FontWeight.w700,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'They\'ll get a gift box to open, with your message inside.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              const PurchaseStatusBanner(
                successText: 'Your gift is on its way 💝',
              ),
              if (subscribed) ...[
                const _SoftNote(
                  text:
                      'You already have Premium together — gift a Memory '
                      'book instead.',
                ),
                const SizedBox(height: 12),
              ],
              for (final id in options) ...[
                _GiftOption(
                  key: Key('gift-$id'),
                  id: id,
                  price: products.value?[id]?.price,
                  selected: id == selected,
                  onTap: () => setState(() => _selected = id),
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 6),
              FrostedForm(
                child: TextField(
                  key: const Key('gift-message'),
                  controller: _message,
                  maxLength: Products.maxGiftMessage,
                  minLines: 3,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Your message',
                    hintText: 'Write something $partner will smile at…',
                    alignLabelWithHint: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '$partner will see: “${me.displayName} gifted you '
                '${what[0].toLowerCase()}${what.substring(1)} 💝”',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('gift-send'),
                onPressed: purchase.busy ? null : () => _send(selected),
                style: pillButtonStyle(context, preset: GradientPreset.festive),
                icon: const Icon(Icons.card_giftcard_rounded),
                label: BusyButtonLabel(
                  busy: purchase.busy,
                  label: price == null ? 'Send gift' : 'Send gift · $price',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GiftOption extends StatelessWidget {
  const _GiftOption({
    super.key,
    required this.id,
    required this.price,
    required this.selected,
    required this.onTap,
  });

  final String id;
  final String? price;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    final book = id == Products.giftBook;
    final preset = book ? GradientPreset.lavender : GradientPreset.gold;
    final accent = preset.isDarkIn(b) ? preset.accent(b) : preset.ink;
    return AnimatedGradientCard(
      preset: preset,
      radius: 22,
      onTap: onTap,
      sheen: false,
      border: Border.all(
        color: selected ? accent : Colors.white.withValues(alpha: .6),
        width: selected ? 2.4 : 1,
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
      child: Row(
        children: [
          IconTile(
            icon: book
                ? Icons.auto_stories_outlined
                : Icons.workspace_premium_outlined,
            preset: preset,
            size: 40,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              Products.label(id),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: preset.foreground(b),
              ),
            ),
          ),
          Text(
            price ?? '',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: preset.foreground(b),
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            selected
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_off_rounded,
            color: accent,
          ),
        ],
      ),
    );
  }
}

class _SoftNote extends StatelessWidget {
  const _SoftNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    const preset = GradientPreset.mint;
    return AnimatedGradientCard(
      key: const Key('gift-subscribed-note'),
      preset: preset,
      radius: 20,
      animate: false,
      sheen: false,
      shadow: false,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(Icons.favorite_rounded, color: preset.ink, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: preset.foreground(b),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
