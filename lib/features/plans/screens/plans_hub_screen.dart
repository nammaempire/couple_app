import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/plans/models/date_plan.dart';
import 'package:couple_app/features/plans/providers/bucket_list_providers.dart';
import 'package:couple_app/features/plans/providers/date_plan_providers.dart';
import 'package:couple_app/features/plans/providers/expense_providers.dart';
import 'package:couple_app/features/plans/providers/place_providers.dart';
import 'package:couple_app/features/plans/providers/wishlist_providers.dart';
import 'package:couple_app/features/plans/screens/bucket_list_screen.dart';
import 'package:couple_app/features/plans/screens/date_planner_screen.dart';
import 'package:couple_app/features/plans/screens/expenses_screen.dart';
import 'package:couple_app/features/plans/screens/places_screen.dart';
import 'package:couple_app/features/plans/screens/wishlist_screen.dart';
import 'package:couple_app/features/plans/widgets/plans_hub_tile.dart';

/// The Plans sub-tab of Together: one tile per shared list, each with a
/// short live summary, opening the full screen.
class PlansHubScreen extends ConsumerWidget {
  const PlansHubScreen({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(datePlansProvider).value;
    final bucket = ref.watch(bucketItemsProvider).value;
    final wishes = ref.watch(wishlistItemsProvider).value;
    final places = ref.watch(placesProvider).value;
    final expenses = ref.watch(expensesProvider).value;

    String? count(List<Object>? list, String one, String many) {
      if (list == null) return null;
      if (list.isEmpty) return null;
      return '${list.length} ${list.length == 1 ? one : many}';
    }

    final upcoming = plans
        ?.where((p) => p.status == DatePlanStatus.planned)
        .length;
    final bucketDone = bucket?.where((b) => b.done).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        PlansHubTile(
          icon: Icons.wine_bar_outlined,
          title: 'Date planner',
          preset: GradientPreset.sunset,
          subtitle: 'Ideas, upcoming dates and how they went',
          summary: upcoming != null && upcoming > 0
              ? '$upcoming coming up'
              : count(plans, 'idea', 'ideas'),
          onTap: () => _open(context, const DatePlannerScreen()),
        ),
        PlansHubTile(
          icon: Icons.checklist_rounded,
          title: 'Bucket list',
          preset: GradientPreset.mint,
          subtitle: 'Things to do together, someday',
          summary: bucket == null || bucket.isEmpty
              ? null
              : '$bucketDone of ${bucket.length} done',
          onTap: () => _open(context, const BucketListScreen()),
        ),
        PlansHubTile(
          icon: Icons.card_giftcard_outlined,
          title: 'Wishlist',
          preset: GradientPreset.blush,
          subtitle: 'Gift ideas for each other',
          summary: count(wishes, 'wish', 'wishes'),
          onTap: () => _open(context, const WishlistScreen()),
        ),
        PlansHubTile(
          icon: Icons.place_outlined,
          title: 'Places',
          preset: GradientPreset.ocean,
          subtitle: 'Where you want to go, and where you have been',
          summary: count(places, 'place', 'places'),
          onTap: () => _open(context, const PlacesScreen()),
        ),
        PlansHubTile(
          icon: Icons.account_balance_wallet_outlined,
          title: 'Shared expenses',
          preset: GradientPreset.lavender,
          subtitle: 'Who paid for what, and who owes whom',
          summary: count(expenses, 'entry', 'entries'),
          onTap: () => _open(context, const ExpensesScreen()),
        ),
      ],
    );
  }
}
