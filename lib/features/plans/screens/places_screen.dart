import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/core/widgets/empty_state.dart';
import 'package:couple_app/features/app_lock/app_lock_controller.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/plans/data/date_plan_service.dart';
import 'package:couple_app/features/plans/data/place_maps_launcher.dart';
import 'package:couple_app/features/plans/data/place_service.dart';
import 'package:couple_app/features/plans/models/place.dart';
import 'package:couple_app/features/plans/providers/date_plan_providers.dart';
import 'package:couple_app/features/plans/providers/place_providers.dart';
import 'package:couple_app/features/plans/screens/date_planner_screen.dart';
import 'package:couple_app/features/plans/screens/place_editor_screen.dart';
import 'package:couple_app/features/plans/widgets/place_been_sheet.dart';
import 'package:couple_app/features/plans/widgets/place_card.dart';
import 'package:couple_app/features/plans/widgets/place_category_chips.dart';
import 'package:couple_app/features/plans/widgets/place_details_sheet.dart';
import 'package:couple_app/features/plans/widgets/places_empty_state.dart';
import 'package:couple_app/features/plans/widgets/soft_kit.dart';

/// Places you want to go together and the ones you've been, with Maps
/// links and "Plan a date here".
class PlacesScreen extends ConsumerStatefulWidget {
  const PlacesScreen({super.key});

  @override
  ConsumerState<PlacesScreen> createState() => _PlacesScreenState();
}

class _PlacesScreenState extends ConsumerState<PlacesScreen>
    with SingleTickerProviderStateMixin {
  late final String _coupleId;
  late final String _myUid;
  late final PlaceService _service;
  late final DatePlanService _datePlans;
  late final TabController _tabs;

  PlaceCategory? _category;
  bool _favouritesOnly = false;

  @override
  void initState() {
    super.initState();
    _coupleId = ref.read(currentCoupleIdProvider);
    _myUid = ref.read(currentUidProvider);
    _service = ref.read(placeServiceProvider);
    _datePlans = ref.read(datePlanServiceProvider);
    _tabs = TabController(length: PlaceStatus.values.length, vsync: this)
      ..addListener(() {
        if (!_tabs.indexIsChanging) setState(() {});
      });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  PlaceStatus get _status => PlaceStatus.values[_tabs.index];

  void _openEditor({Place? place}) {
    Navigator.of(context).push(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => PlaceEditorScreen(place: place, initialStatus: _status),
      ),
    );
  }

  /// Runs [action], showing [failure] if it throws. Returns whether it
  /// succeeded, so callers only celebrate real saves.
  Future<bool> _run(Future<void> Function() action, String failure) async {
    try {
      await action();
      return true;
    } catch (_) {
      if (mounted) context.showSnackMessage(failure);
      return false;
    }
  }

  Future<void> _openMaps(Place place) async {
    final ok = await ref
        .read(appLockControllerProvider.notifier)
        .suspendWhile(launchPlaceInMaps(place));
    if (!ok && mounted) context.showSnackMessage('Could not open Maps.');
  }

  Future<void> _toggleFavourite(Place place) => _run(
    () => _service.setFavourite(_coupleId, place.id, !place.favourite),
    'Could not save. Check your connection.',
  );

  Future<void> _planDate(Place place) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await _datePlans.save(_coupleId, place.toDateIdea(_myUid));
    } catch (_) {
      if (!mounted) return;
      context.showSnackMessage('Could not save. Check your connection.');
      return;
    }
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text('“Date at ${place.name}” added to your date ideas.'),
        action: SnackBarAction(
          label: 'View',
          onPressed: () => navigator.push(
            MaterialPageRoute<void>(builder: (_) => const DatePlannerScreen()),
          ),
        ),
      ),
    );
  }

  Future<void> _markBeen(Place place) async {
    final visit = await showModalBottomSheet<PlaceVisit>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => PlaceBeenSheet(place: place),
    );
    if (visit == null) return;
    final ok = await _run(
      () => _service.markBeen(
        _coupleId,
        place.id,
        visitedAt: visit.visitedAt,
        rating: visit.rating,
        notes: visit.notes,
      ),
      'Could not save. Check your connection.',
    );
    if (ok && mounted && _tabs.index == 0) _tabs.animateTo(1);
  }

  Future<void> _delete(Place place) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this place?'),
        content: const Text('This removes it for both of you.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(
      () => _service.delete(_coupleId, place.id),
      'Could not delete. Check your connection.',
    );
  }

  Future<void> _showDetails(Place place) async {
    final partnerName = ref.read(partnerNameProvider);
    final action = await showModalBottomSheet<PlaceAction>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => PlaceDetailsSheet(
        place: place,
        addedBy: place.createdBy == _myUid ? 'you' : partnerName,
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case PlaceAction.openMaps:
        await _openMaps(place);
      case PlaceAction.planDate:
        await _planDate(place);
      case PlaceAction.markBeen:
        await _markBeen(place);
      case PlaceAction.markWantToGo:
        await _run(
          () => _service.markWantToGo(_coupleId, place.id),
          'Could not save. Check your connection.',
        );
      case PlaceAction.edit:
        _openEditor(place: place);
      case PlaceAction.delete:
        await _delete(place);
    }
  }

  Widget _list(List<Place> all, PlaceStatus status, String partnerName) {
    final shown = PlaceLists.filter(
      all,
      status: status,
      category: _category,
      favouritesOnly: _favouritesOnly,
    );
    if (shown.isEmpty) {
      final filtering =
          (_category != null || _favouritesOnly) &&
          PlaceLists.count(all, status) > 0;
      return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: PlacesEmptyState(
              status: status,
              filtering: filtering,
              partnerName: partnerName,
              onAdd: _openEditor,
              onClearFilters: () => setState(() {
                _category = null;
                _favouritesOnly = false;
              }),
            ),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 96),
      children: [
        ...staggered([
          for (final p in shown)
            PlaceCard(
              key: ValueKey(p.id),
              place: p,
              onTap: () => _showDetails(p),
              onToggleFavourite: () => _toggleFavourite(p),
              onOpenMaps: () => _openMaps(p),
            ),
        ]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final places = ref.watch(placesProvider);
    final partnerName = ref.watch(partnerNameProvider);
    final all = places.value ?? const <Place>[];
    final categories = PlaceLists.categoriesUsed(all);
    // Keep the selected filter visible even if its last place went away.
    final chipCategories = _category == null || categories.contains(_category)
        ? categories
        : [...categories, _category!];

    String tabLabel(PlaceStatus s) {
      final n = PlaceLists.count(all, s);
      return n == 0 ? s.label : '${s.label} · $n';
    }

    final Widget body;
    if (!places.hasValue && !places.hasError) {
      body = const Center(child: CircularProgressIndicator());
    } else if (!places.hasValue) {
      body = const EmptyState(
        icon: Icons.cloud_off,
        text: 'Could not load your places.',
      );
    } else {
      body = Column(
        children: [
          if (all.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: PlaceCategoryChips(
                categories: chipCategories,
                selected: _category,
                onSelected: (c) => setState(() => _category = c),
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                for (final s in PlaceStatus.values) _list(all, s, partnerName),
              ],
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Places'),
        actions: [
          IconButton(
            tooltip: _favouritesOnly ? 'Show all places' : 'Favourites only',
            isSelected: _favouritesOnly,
            onPressed: () => setState(() => _favouritesOnly = !_favouritesOnly),
            icon: const Icon(Icons.favorite_border),
            selectedIcon: Icon(
              Icons.favorite,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: [for (final s in PlaceStatus.values) Tab(text: tabLabel(s))],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-place',
        onPressed: _openEditor,
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Add place'),
      ),
      body: body,
    );
  }
}
