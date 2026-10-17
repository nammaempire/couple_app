import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/features/memories/models/memory.dart';
import 'package:couple_app/features/memories/widgets/memory_recap_collage.dart';
import 'package:couple_app/features/memories/widgets/memory_recap_info_line.dart';
import 'package:couple_app/features/memories/widgets/memory_recap_stat.dart';

/// "Our Memories": a look back at one month or one year, built on the device
/// from the memories you have added.
class MemoryRecapScreen extends StatefulWidget {
  const MemoryRecapScreen({super.key, required this.memories});

  final List<Memory> memories;

  @override
  State<MemoryRecapScreen> createState() => _MemoryRecapScreenState();
}

class _MemoryRecapScreenState extends State<MemoryRecapScreen> {
  bool _yearly = false;
  late DateTime _period = _latestPeriod();

  /// Starts on the newest month that has memories.
  DateTime _latestPeriod() {
    if (widget.memories.isEmpty) {
      final now = DateTime.now();
      return DateTime(now.year, now.month);
    }
    final newest = widget.memories
        .map((m) => m.date)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    return DateTime(newest.year, newest.month);
  }

  MemoryRecap get _recap => _yearly
      ? MemoryRecap.year(widget.memories, _period.year)
      : MemoryRecap.month(widget.memories, _period.year, _period.month);

  void _step(int delta) {
    setState(() {
      _period = _yearly
          ? DateTime(_period.year + delta, _period.month)
          : DateTime(_period.year, _period.month + delta);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recap = _recap;
    final highlights = recap.highlights(6);
    final now = DateTime.now();
    final atLatest = _yearly
        ? _period.year >= now.year
        : !DateTime(
            _period.year,
            _period.month + 1,
          ).isBefore(DateTime(now.year, now.month + 1));

    return Scaffold(
      appBar: AppBar(title: const Text('Our Memories')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Center(
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('Month')),
                ButtonSegment(value: true, label: Text('Year')),
              ],
              selected: {_yearly},
              onSelectionChanged: (s) => setState(() => _yearly = s.first),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton(
                tooltip: 'Earlier',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _step(-1),
              ),
              Expanded(
                child: Text(
                  recap.label,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Later',
                icon: const Icon(Icons.chevron_right),
                onPressed: atLatest ? null : () => _step(1),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (recap.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Text(
                'No memories from ${recap.label} yet.',
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            )
          else ...[
            if (highlights.isNotEmpty) MemoryRecapCollage(urls: highlights),
            const SizedBox(height: 16),
            Row(
              children: [
                MemoryRecapStat(
                  value: recap.memories.length,
                  label: 'memories',
                ),
                MemoryRecapStat(value: recap.photoCount, label: 'photos'),
                MemoryRecapStat(value: recap.videoCount, label: 'videos'),
                MemoryRecapStat(value: recap.places.length, label: 'places'),
              ],
            ),
            const SizedBox(height: 16),
            if (recap.topAlbum != null)
              MemoryRecapInfoLine(
                icon: Icons.photo_album_outlined,
                text:
                    'Most of it was '
                    '${MemoryAlbums.emojiFor(recap.topAlbum!)} ${recap.topAlbum}',
              ),
            if (recap.places.isNotEmpty)
              MemoryRecapInfoLine(
                icon: Icons.place_outlined,
                text: recap.places.take(4).join(' · '),
              ),
            const SizedBox(height: 12),
            Text(
              'Moments',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            for (final m in recap.memories)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: m.coverUrl == null
                        ? Container(
                            color: theme.colorScheme.primaryContainer,
                            child: Center(
                              child: Text(MemoryAlbums.emojiFor(m.album)),
                            ),
                          )
                        : CachedNetworkImage(
                            imageUrl: m.coverUrl!,
                            fit: BoxFit.cover,
                          ),
                  ),
                ),
                title: Text(m.title.isEmpty ? 'Untitled' : m.title),
                subtitle: Text(
                  [
                    DateFormat.MMMd().format(m.date),
                    if (m.place != null) m.place!,
                  ].join(' · '),
                ),
                trailing: m.favorite
                    ? Icon(Icons.favorite, color: theme.colorScheme.primary)
                    : null,
              ),
          ],
        ],
      ),
    );
  }
}
