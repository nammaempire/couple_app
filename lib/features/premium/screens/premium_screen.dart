import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/floating_hearts.dart';
import 'package:couple_app/core/widgets/glass.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/onboarding/widgets/busy_button_label.dart';
import 'package:couple_app/features/onboarding/widgets/romance_kit.dart';
import 'package:couple_app/features/premium/models/premium_status.dart';
import 'package:couple_app/features/premium/models/products.dart';
import 'package:couple_app/features/premium/providers/premium_providers.dart';
import 'package:couple_app/features/premium/screens/gift_composer_screen.dart';
import 'package:couple_app/features/premium/widgets/purchase_status_banner.dart';

/// "Premium until 4 Nov 2027".
String premiumUntilText(DateTime until) =>
    'Premium until ${DateFormat('d MMM y').format(until)}';

/// Premium for the two of you: the plans with the store's prices (yearly
/// first, as the best value), what Premium brings (most of it still to
/// come; nothing in the app is locked), restore, and gifting.
class PremiumScreen extends ConsumerStatefulWidget {
  const PremiumScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const PremiumScreen());

  static final productKey = Products.subscriptions.join(',');

  @override
  ConsumerState<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends ConsumerState<PremiumScreen> {
  String _selected = Products.premiumYearly;

  void _buy() {
    ref
        .read(purchaseControllerProvider.notifier)
        .buy(_selected, coupleId: ref.read(currentCoupleIdProvider));
  }

  void _restore() {
    ref
        .read(purchaseControllerProvider.notifier)
        .restore(ref.read(currentCoupleIdProvider));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final premium = ref.watch(premiumProvider);
    final now = ref.watch(premiumClockProvider)();
    final active = premium?.isActive(now) ?? false;
    final subscribed = premium?.hasActiveSubscription(now) ?? false;
    final products = ref.watch(storeProductsProvider(PremiumScreen.productKey));
    final purchase = ref.watch(purchaseControllerProvider);
    final storeEmpty = products.hasValue && products.value!.isEmpty;

    StoreProduct? product(String id) => products.value?[id];

    return RomanceBackdrop(
      preset: GradientPreset.gold,
      strength: .5,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: romanceAppBar(
          automaticallyImplyLeading: true,
          title: const Text('Premium'),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              _Hero(premium: active ? premium : null),
              const SizedBox(height: 16),
              const PurchaseStatusBanner(
                successText: 'Thank you! Premium is on for both of you.',
              ),
              if (!subscribed) ...[
                _PlanCard(
                  key: const Key('plan-yearly'),
                  id: Products.premiumYearly,
                  title: 'Yearly',
                  price: product(Products.premiumYearly)?.price,
                  period: 'a year',
                  note: 'Best value',
                  selected: _selected == Products.premiumYearly,
                  onTap: () =>
                      setState(() => _selected = Products.premiumYearly),
                ),
                const SizedBox(height: 10),
                _PlanCard(
                  key: const Key('plan-monthly'),
                  id: Products.premiumMonthly,
                  title: 'Monthly',
                  price: product(Products.premiumMonthly)?.price,
                  period: 'a month',
                  selected: _selected == Products.premiumMonthly,
                  onTap: () =>
                      setState(() => _selected = Products.premiumMonthly),
                ),
                const SizedBox(height: 8),
                Text(
                  storeEmpty
                      ? 'Google Play isn\'t available right now, so prices '
                            'can\'t be shown. Try again later.'
                      : 'One purchase covers both of you. Renews until you '
                            'cancel in Google Play.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  key: const Key('premium-buy'),
                  onPressed: purchase.busy || storeEmpty ? null : _buy,
                  style: pillButtonStyle(
                    context,
                    preset: GradientPreset.festive,
                  ),
                  child: BusyButtonLabel(
                    busy: purchase.busy,
                    label: active
                        ? 'Switch to ${_selected == Products.premiumYearly ? 'yearly' : 'monthly'}'
                        : 'Get Premium',
                  ),
                ),
              ] else
                GlassPanel(
                  dark: theme.brightness == Brightness.dark,
                  radius: 20,
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    'Your ${premium!.plan} plan renews in Google Play. You can '
                    'change or cancel it there any time.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              const SizedBox(height: 22),
              const _Benefits(),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: () =>
                    Navigator.of(context).push(GiftComposerScreen.route()),
                style: pillOutlineStyle(
                  context,
                  preset: GradientPreset.festive,
                ),
                icon: const Icon(Icons.card_giftcard_rounded),
                label: const Text('Send a gift'),
              ),
              const SizedBox(height: 4),
              TextButton(
                key: const Key('premium-restore'),
                onPressed: purchase.busy ? null : _restore,
                child: const Text('Restore purchases'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.premium});

  /// Set while Premium is active.
  final PremiumStatus? premium;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const preset = GradientPreset.night;
    final b = theme.brightness;
    final p = premium;
    return AnimatedGradientCard(
      preset: preset,
      radius: 30,
      padding: EdgeInsets.zero,
      child: Stack(
        children: [
          const Positioned.fill(
            child: FloatingHearts(
              count: 10,
              style: ParticleStyle.confetti,
              opacity: .35,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
            child: Column(
              children: [
                const GlowBadge(
                  preset: GradientPreset.gold,
                  icon: Icons.workspace_premium_rounded,
                  size: 70,
                ),
                const SizedBox(height: 14),
                Text(
                  p == null ? 'Us Premium' : 'You have Premium',
                  style: romanceSerif(theme.textTheme.headlineSmall).copyWith(
                    fontWeight: FontWeight.w700,
                    fontStyle: FontStyle.italic,
                    color: preset.foreground(b),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  p == null
                      ? 'One plan for both of you, to keep this space growing.'
                      : 'For both of you · ${p.plan == 'gift' ? 'a gift' : '${p.plan} plan'}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: preset.foregroundMuted(b),
                  ),
                ),
                if (p != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    key: const Key('premium-until'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      premiumUntilText(p.until),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: preset.accent(b),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    super.key,
    required this.id,
    required this.title,
    required this.price,
    required this.period,
    required this.selected,
    required this.onTap,
    this.note,
  });

  final String id;
  final String title;
  final String? price;
  final String period;
  final String? note;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    final preset = note != null
        ? GradientPreset.festive
        : GradientPreset.lavender;
    final accent = preset.isDarkIn(b) ? preset.accent(b) : preset.ink;
    return Semantics(
      selected: selected,
      button: true,
      child: AnimatedGradientCard(
        preset: preset,
        radius: 22,
        onTap: onTap,
        border: Border.all(
          color: selected ? accent : Colors.white.withValues(alpha: .6),
          width: selected ? 2.4 : 1,
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: accent,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text(
                        title,
                        style: romanceSerif(theme.textTheme.titleLarge)
                            .copyWith(
                              fontWeight: FontWeight.w700,
                              color: preset.foreground(b),
                            ),
                      ),
                      if (note != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            note!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Billed $period',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: preset.foregroundMuted(b),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              price ?? '—',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: preset.foreground(b),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Benefits extends StatelessWidget {
  const _Benefits();

  static const _items = [
    (Icons.people_alt_outlined, 'One plan, both of you', null),
    (Icons.favorite_border_rounded, 'Helps keep Us growing', null),
    (Icons.auto_stories_outlined, 'A memory book every year', 'Coming soon'),
    (Icons.hd_outlined, 'Full-quality photos and videos', 'Coming soon'),
    (Icons.palette_outlined, 'More chat themes and stickers', 'Coming soon'),
    (Icons.lock_outline_rounded, 'More room in Private', 'Coming soon'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GradientGroup(
      preset: GradientPreset.lavender,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
          child: Text(
            'What Premium brings',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        for (final (icon, title, soon) in _items)
          ListTile(
            dense: true,
            leading: Icon(icon),
            title: Text(title),
            trailing: soon == null
                ? const Icon(Icons.check_rounded)
                : Text(
                    soon,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 2, 18, 12),
          child: Text(
            'Everything you use today stays free.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
