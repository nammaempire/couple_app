import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/memories/models/memory.dart';
import 'package:couple_app/features/memories/providers/memory_providers.dart';
import 'package:couple_app/features/memories/screens/memory_detail_screen.dart';
import 'package:couple_app/features/memories/screens/memory_editor_screen.dart';
import 'package:couple_app/features/memories/screens/memory_recap_screen.dart';
import 'package:couple_app/features/memories/widgets/memories_empty_state.dart';
import 'package:couple_app/features/memories/widgets/memory_card.dart';
import 'package:couple_app/features/memories/widgets/memory_filter_chips.dart';
import 'package:couple_app/features/memories/widgets/memory_highlights.dart';
import 'package:couple_app/features/plans/widgets/soft_kit.dart';

/// The Memories tab: a timeline of shared moments, with albums, favourites,
/// search and a monthly recap.
class MemoriesScreen extends ConsumerStatefulWidget {
  const MemoriesScreen({super.key});

  @override
  ConsumerState<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends ConsumerState<MemoriesScreen> {
  late final String _coupleId;

  String _filter = MemoryFilterChips.allFilter;
  DateTimeRange? _range;
  bool _searching = false;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _coupleId = ref.read(currentCoupleIdProvider);
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Memory> _apply(List<Memory> all) {
    return all.where((m) {
      if (_filter == MemoryFilterChips.favouritesFilter && !m.favorite) {
        return false;
      }
      if (_filter != MemoryFilterChips.allFilter &&
          _filter != MemoryFilterChips.favouritesFilter &&
          m.album != _filter) {
        return false;
      }
      final range = _range;
      if (range != null) {
        final day = DateTime(m.date.year, m.date.month, m.date.day);
        if (day.isBefore(range.start) || day.isAfter(range.end)) return false;
      }
      return m.matches(_search.text);
    }).toList();
  }

  Future<void> _pickRange(List<Memory> all) async {
    final now = DateTime.now();
    final earliest = all.isEmpty
        ? DateTime(now.year - 5)
        : all.map((m) => m.date).reduce((a, b) => a.isBefore(b) ? a : b);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(earliest.year - 1),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _range,
      helpText: 'Show memories between',
    );
    if (picked != null) setState(() => _range = picked);
  }

  void _openEditor({Memory? memory, List<String> albums = const []}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            MemoryEditorScreen(memory: memory, existingAlbums: albums),
      ),
    );
  }

  void _openDetail(Memory memory, List<String> albums) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MemoryDetailScreen(
          memoryId: memory.id,
          initial: memory,
          albums: albums,
        ),
      ),
    );
  }

  void _openRecap(List<Memory> all) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => MemoryRecapScreen(memories: all)));
  }

  @override
  Widget build(BuildContext context) {
    final memories = ref.watch(memoriesProvider);
    final all = memories.value ?? const <Memory>[];
    final albums = MemoryAlbums.all(all);
    final shown = _apply(all);
    final filtering =
        _filter != MemoryFilterChips.allFilter ||
        _range != null ||
        _search.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search title, place, caption',
                  filled: false,
                  border: InputBorder.none,
                ),
              )
            : const Text('Memories'),
        actions: [
          IconButton(
            tooltip: _searching ? 'Close search' : 'Search',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) _search.clear();
            }),
          ),
          IconButton(
            tooltip: 'Filter by date',
            icon: Icon(
              _range == null ? Icons.date_range_outlined : Icons.date_range,
            ),
            onPressed: () => _pickRange(all),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(albums: albums),
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('New memory'),
      ),
      body: !memories.hasValue && !memories.hasError
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: MemoryFilterChips(
                    albums: albums,
                    selected: _filter,
                    onSelected: (f) => setState(() => _filter = f),
                  ),
                ),
                if (_range != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: InputChip(
                        avatar: const Icon(Icons.date_range, size: 18),
                        label: Text(
                          '${DateFormat.yMMMd().format(_range!.start)} – '
                          '${DateFormat.yMMMd().format(_range!.end)}',
                        ),
                        onDeleted: () => setState(() => _range = null),
                      ),
                    ),
                  ),
                if (!filtering && all.isNotEmpty)
                  SliverToBoxAdapter(
                    child: MemoryHighlights(
                      all: all,
                      onOpenRecap: () => _openRecap(all),
                      onOpenMemory: (m) => _openDetail(m, albums),
                    ),
                  ),
                if (shown.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: MemoriesEmptyState(
                      filtering: filtering,
                      onCreate: () => _openEditor(albums: albums),
                    ),
                  )
                else
                  ..._timeline(context, shown, albums),
                const SliverToBoxAdapter(child: SizedBox(height: 96)),
              ],
            ),
    );
  }

  /// Month headers followed by that month's memory cards.
  List<Widget> _timeline(
    BuildContext context,
    List<Memory> memories,
    List<String> albums,
  ) {
    final groups = <String, List<Memory>>{};
    for (final m in memories) {
      groups.putIfAbsent(DateFormat.yMMMM().format(m.date), () => []).add(m);
    }

    var index = 0;
    return [
      for (final entry in groups.entries) ...[
        SliverToBoxAdapter(
          child: SoftSectionHeader(
            label: entry.key,
            count: entry.value.length,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
          ),
        ),
        SliverList.list(
          children: [
            for (final memory in entry.value)
              stagger(
                index++,
                key: ValueKey(memory.id),
                MemoryCard(
                  memory: memory,
                  onTap: () => _openDetail(memory, albums),
                  onToggleFavourite: () => ref
                      .read(memoryServiceProvider)
                      .setFavorite(
                        coupleId: _coupleId,
                        memoryId: memory.id,
                        favorite: !memory.favorite,
                      ),
                ),
              ),
          ],
        ),
      ],
    ];
  }
}
