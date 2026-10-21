import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/memories/models/memory.dart';
import 'package:couple_app/features/memories/widgets/memory_look.dart';
import 'package:couple_app/features/memories/widgets/memory_recap_collage.dart';
import 'package:couple_app/features/memories/widgets/memory_recap_info_line.dart';
import 'package:couple_app/features/memories/widgets/memory_recap_stat.dart';
import 'package:couple_app/features/plans/widgets/soft_kit.dart';

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

    final b = theme.brightness;
    const preset = GradientPreset.festive;
    final fg = preset.foreground(b);
    final fgMuted = preset.foregroundMuted(b);
    final tile = Colors.white.withValues(alpha: preset.isDarkIn(b) ? .12 : .6);
    final navStyle = IconButton.styleFrom(
      backgroundColor: tile,
      foregroundColor: fg,
      disabledForegroundColor: fg.withValues(alpha: .3),
    );

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
          const SizedBox(height: 14),
          AnimatedGradientCard(
            preset: preset,
            radius: 26,
            padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Earlier',
                      style: navStyle,
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => _step(-1),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            _yearly ? 'YOUR YEAR' : 'YOUR MONTH',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: presetAccentText(preset, b),
                              letterSpacing: 1.4,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            recap.label,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: fg,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Later',
                      style: navStyle,
                      icon: const Icon(Icons.chevron_right),
                      onPressed: atLatest ? null : () => _step(1),
                    ),
                  ],
                ),
                if (!recap.isEmpty) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      for (final (value, label) in [
                        (recap.memories.length, 'memories'),
                        (recap.photoCount, 'photos'),
                        (recap.videoCount, 'videos'),
                        (recap.places.length, 'places'),
                      ])
                        MemoryRecapStat(
                          value: value,
                          label: label,
                          color: fg,
                          mutedColor: fgMuted,
                          tile: tile,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (recap.isEmpty)
            GradientEmptyState(
              emoji: '🗓️',
              preset: GradientPreset.lavender,
              padding: const EdgeInsets.symmetric(vertical: 32),
              text: 'No memories from ${recap.label} yet.',
            )
          else ...[
            if (highlights.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: MemoryRecapCollage(urls: highlights),
              ),
              const SizedBox(height: 16),
            ],
            if (recap.topAlbum != null || recap.places.isNotEmpty)
              TintedCard(
                preset: GradientPreset.lavender,
                strength: .5,
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Column(
                  children: [
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
                  ],
                ),
              ),
            SoftSectionHeader(
              label: 'Moments',
              count: recap.memories.length,
              padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
            ),
            for (final (i, m) in recap.memories.indexed)
              stagger(i, key: ValueKey(m.id), _moment(context, m)),
          ],
        ],
      ),
    );
  }

  Widget _moment(BuildContext context, Memory m) {
    final theme = Theme.of(context);
    final preset = MemoryLook.presetFor(m.album);
    return TintedCard(
      preset: preset,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 48,
              height: 48,
              child: m.coverUrl == null
                  ? EmojiBadge(
                      emoji: MemoryAlbums.emojiFor(m.album),
                      preset: preset,
                      size: 48,
                    )
                  : CachedNetworkImage(
                      imageUrl: m.coverUrl!,
                      fit: BoxFit.cover,
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.title.isEmpty ? 'Untitled' : m.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  [
                    DateFormat.MMMd().format(m.date),
                    if (m.place != null) m.place!,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (m.favorite)
            Icon(Icons.favorite, color: theme.colorScheme.primary),
        ],
      ),
    );
  }
}
