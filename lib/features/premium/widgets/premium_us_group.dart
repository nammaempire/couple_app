import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/books/providers/book_providers.dart';
import 'package:couple_app/features/books/screens/memory_books_screen.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/onboarding/widgets/romance_kit.dart';
import 'package:couple_app/features/premium/providers/premium_providers.dart';
import 'package:couple_app/features/premium/screens/gift_composer_screen.dart';
import 'package:couple_app/features/premium/screens/gift_reveal_screen.dart';
import 'package:couple_app/features/premium/screens/premium_screen.dart';

/// The Us tab's Premium, Memory books and gifts rows, with a waiting gift
/// on top when there is one.
class PremiumUsGroup extends ConsumerWidget {
  const PremiumUsGroup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final premium = ref.watch(premiumProvider);
    final active = ref.watch(isPremiumProvider);
    final gifts = ref.watch(unopenedGiftsProvider);
    final credits = ref.watch(bookCreditsProvider);
    final books = ref.watch(booksProvider).value?.length ?? 0;
    final partner = ref.watch(partnerNameProvider);
    final theme = Theme.of(context);
    const preset = GradientPreset.gold;
    final b = theme.brightness;

    return GradientGroup(
      key: const Key('premium-us-group'),
      preset: preset,
      children: [
        if (gifts.isNotEmpty)
          ListTile(
            key: const Key('us-gift-row'),
            leading: const Text('🎁', style: TextStyle(fontSize: 22)),
            title: Text(
              '$partner sent you a gift',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text('Tap to open'),
            trailing: Badge(
              label: Text('${gifts.length}'),
              backgroundColor: preset.isDarkIn(b)
                  ? preset.accent(b)
                  : preset.ink,
            ),
            onTap: () =>
                Navigator.of(context).push(GiftRevealScreen.route(gifts.first)),
          ),
        ListTile(
          key: const Key('us-premium-row'),
          leading: const Icon(Icons.workspace_premium_outlined),
          title: const Text('Premium'),
          subtitle: Text(
            active && premium != null
                ? premiumUntilText(premium.until)
                : 'One plan for both of you',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(PremiumScreen.route()),
        ),
        ListTile(
          key: const Key('us-books-row'),
          leading: const Icon(Icons.auto_stories_outlined),
          title: const Text('Memory books'),
          subtitle: Text(
            credits > 0
                ? (credits == 1
                      ? '1 book ready to make'
                      : '$credits books ready to make')
                : books == 0
                ? 'Your story as a book'
                : books == 1
                ? '1 book'
                : '$books books',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MemoryBooksScreen.route()),
        ),
        ListTile(
          leading: const Icon(Icons.card_giftcard_outlined),
          title: const Text('Send a gift'),
          subtitle: Text('Premium or a Memory book, for $partner'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(GiftComposerScreen.route()),
        ),
      ],
    );
  }
}
