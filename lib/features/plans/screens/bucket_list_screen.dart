import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/core/widgets/empty_state.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/plans/data/bucket_list_service.dart';
import 'package:couple_app/features/plans/models/bucket_item.dart';
import 'package:couple_app/features/plans/models/bucket_progress.dart';
import 'package:couple_app/features/plans/providers/bucket_list_providers.dart';
import 'package:couple_app/features/plans/screens/bucket_item_editor_screen.dart';
import 'package:couple_app/features/plans/widgets/bucket_category_chips.dart';
import 'package:couple_app/features/plans/widgets/bucket_item_tile.dart';
import 'package:couple_app/features/plans/widgets/bucket_progress_header.dart';
import 'package:couple_app/features/plans/widgets/bucket_quick_add_sheet.dart';
import 'package:couple_app/features/plans/widgets/bucket_section_header.dart';
import 'package:couple_app/features/plans/widgets/soft_kit.dart';

/// The shared bucket list: progress, category filters, and things to do
/// someday, ticked off together.
class BucketListScreen extends ConsumerStatefulWidget {
  const BucketListScreen({super.key});

  @override
  ConsumerState<BucketListScreen> createState() => _BucketListScreenState();
}

class _BucketListScreenState extends ConsumerState<BucketListScreen> {
  late final String _coupleId;
  late final String _myUid;
  late final BucketListService _service;

  BucketCategory? _filter;

  /// Items ticked off a moment ago, so their tile plays a little pop.
  final _justDone = <String>{};
  final _celebrationTimers = <Timer>[];

  @override
  void initState() {
    super.initState();
    _coupleId = ref.read(currentCoupleIdProvider);
    _myUid = ref.read(currentUidProvider);
    _service = ref.read(bucketListServiceProvider);
  }

  @override
  void dispose() {
    for (final t in _celebrationTimers) {
      t.cancel();
    }
    super.dispose();
  }

  Future<void> _quickAdd() async {
    final draft = await showModalBottomSheet<BucketItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => BucketQuickAddSheet(initialCategory: _filter),
    );
    if (draft != null && mounted) _openEditor(draft);
  }

  void _openEditor(BucketItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => BucketItemEditorScreen(item: item),
      ),
    );
  }

  Future<void> _toggle(BucketItem item) async {
    final done = !item.done;
    if (done) {
      unawaited(HapticFeedback.mediumImpact());
      setState(() => _justDone.add(item.id));
      _celebrationTimers.add(
        Timer(const Duration(seconds: 2), () {
          if (mounted) setState(() => _justDone.remove(item.id));
        }),
      );
    } else {
      unawaited(HapticFeedback.selectionClick());
    }
    try {
      await _service.setDone(
        coupleId: _coupleId,
        itemId: item.id,
        done: done,
        uid: _myUid,
      );
    } catch (_) {
      if (!mounted) return;
      context.showSnackMessage('Could not update. Check your connection.');
    }
  }

  String? _whoDid(BucketItem item, String partnerName) {
    final by = item.doneBy;
    if (by == null) return null;
    return by == _myUid ? 'you' : partnerName;
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(bucketItemsProvider);
    final partnerName = ref.watch(partnerNameProvider);
    final all = items.value ?? const <BucketItem>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Bucket list')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-bucket-item',
        onPressed: _quickAdd,
        icon: const Icon(Icons.add),
        label: const Text('Add a dream'),
      ),
      body: _body(items, all, partnerName),
    );
  }

  Widget _body(
    AsyncValue<List<BucketItem>> items,
    List<BucketItem> all,
    String partnerName,
  ) {
    if (!items.hasValue && !items.hasError) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!items.hasValue && items.hasError) {
      return const EmptyState(
        icon: Icons.cloud_off,
        text: 'Could not load your bucket list.',
      );
    }
    if (all.isEmpty) {
      return GradientEmptyState(
        emoji: '🌠',
        preset: GradientPreset.sunny,
        scrollable: true,
        text:
            'No dreams on the list yet.\n'
            'Add the things you and $partnerName want to do someday.',
      );
    }

    final shown = BucketProgress.filter(all, _filter);
    final toDo = BucketProgress.toDo(shown);
    final done = BucketProgress.completed(shown);

    Widget tile(BucketItem item) => BucketItemTile(
      key: ValueKey(item.id),
      item: item,
      doneByName: _whoDid(item, partnerName),
      celebrate: _justDone.contains(item.id),
      onToggle: () => _toggle(item),
      onTap: () => _openEditor(item),
    );

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: BucketProgressHeader(
            progress: BucketProgress.of(shown),
            categoryLabel: _filter == null
                ? null
                : '${_filter!.emoji} ${_filter!.label}',
          ),
        ),
        SliverToBoxAdapter(
          child: BucketCategoryChips(
            selected: _filter,
            counts: BucketProgress.countByCategory(all),
            onSelected: (c) => setState(() => _filter = c),
          ),
        ),
        if (shown.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: GradientEmptyState(
              emoji: _filter?.emoji ?? '✨',
              preset: _filter == null
                  ? GradientPreset.sunny
                  : BucketLook.presetFor(_filter!),
              text: 'Nothing in ${_filter?.label ?? 'this list'} yet.',
            ),
          ),
        if (toDo.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: BucketSectionHeader(label: 'To do', count: toDo.length),
          ),
          SliverList.builder(
            itemCount: toDo.length,
            itemBuilder: (context, i) =>
                stagger(i, tile(toDo[i]), key: ValueKey(toDo[i].id)),
          ),
        ],
        if (done.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: BucketSectionHeader(label: 'Done', count: done.length),
          ),
          SliverList.builder(
            itemCount: done.length,
            itemBuilder: (context, i) => tile(done[i]),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ],
    );
  }
}
