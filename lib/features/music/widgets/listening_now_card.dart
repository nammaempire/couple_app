import 'dart:async';

import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/entrance_animation.dart';
import 'package:couple_app/core/widgets/floating_hearts.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/music/data/media_shelf.dart';
import 'package:couple_app/features/music/data/server_clock.dart';
import 'package:couple_app/features/music/models/listening_session.dart';
import 'package:couple_app/features/music/widgets/on_gradient_theme.dart';
import 'package:couple_app/features/music/widgets/song_artwork.dart';

/// "Starting…", "Playing" or "Paused".
String listeningStatusLabel(ListeningSession s, int nowMs) =>
    switch (s.status) {
      ListeningStatus.countdown when !s.countdownDone(nowMs) => 'Starting…',
      ListeningStatus.countdown || ListeningStatus.playing => 'Playing',
      ListeningStatus.paused => 'Paused',
      ListeningStatus.ended => 'Ended',
    };

/// The live session at the top of the library, with a way back in.
///
/// Ticks once a second while counting down, so "Starting…" turns into
/// "Playing" on time.
class ListeningNowCard extends StatefulWidget {
  const ListeningNowCard({
    super.key,
    required this.session,
    required this.clock,
    required this.partnerUid,
    required this.partnerName,
    required this.onOpen,
    this.shelf = MediaShelf.songs,
    this.preset = GradientPreset.blush,
    this.particles,
  });

  /// The card's gradient (from the playing song's moment).
  final GradientPreset preset;

  /// Particles drifting inside the card, or null for none.
  final ParticleStyle? particles;

  final ListeningSession session;
  final ServerClock clock;
  final MediaShelf shelf;
  final String? partnerUid;
  final String partnerName;
  final VoidCallback onOpen;

  @override
  State<ListeningNowCard> createState() => _ListeningNowCardState();
}

class _ListeningNowCardState extends State<ListeningNowCard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _updateTicker();
  }

  @override
  void didUpdateWidget(ListeningNowCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  bool get _counting {
    final s = widget.session;
    return s.status == ListeningStatus.countdown &&
        !s.countdownDone(widget.clock.nowMs());
  }

  void _updateTicker() {
    if (!_counting) {
      _ticker?.cancel();
      _ticker = null;
      return;
    }
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (!_counting) {
        _ticker?.cancel();
        _ticker = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = widget.session;
    final nowMs = widget.clock.nowMs();
    final partnerUid = widget.partnerUid;
    final partnerName = widget.partnerName;
    final partnerListening =
        partnerUid != null && session.isListening(partnerUid, nowMs);
    final who = partnerListening
        ? '$partnerName is ${widget.shelf.doing}'
        : '$partnerName isn’t ${widget.shelf.doing} yet';

    final preset = widget.preset;
    final accent = OnGradientTheme.ink(preset, theme.brightness);
    final particles = widget.particles;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: AnimatedGradientCard(
        preset: preset,
        onTap: widget.onOpen,
        radius: 24,
        padding: EdgeInsets.zero,
        glow: accent,
        child: OnGradientTheme(
          preset: preset,
          child: Stack(
            children: [
              if (particles != null)
                Positioned.fill(
                  child: FloatingHearts(
                    style: particles,
                    count: 8,
                    opacity: .45,
                    color: preset.isDarkIn(theme.brightness)
                        ? accent
                        : Colors.white,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 14, 14, 14),
                child: Row(
                  children: [
                    Pulse(
                      builder: (context, v, child) => DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(alpha: .25 + v * .25),
                              blurRadius: 10 + v * 8,
                            ),
                          ],
                        ),
                        child: child,
                      ),
                      child: SongArtwork(
                        url: session.thumbnailUrl,
                        source: session.source,
                        size: 60,
                        radius: 16,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                widget.shelf == MediaShelf.videos
                                    ? Icons.live_tv_rounded
                                    : Icons.graphic_eq_rounded,
                                size: 16,
                                color: accent,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  widget.shelf.togetherTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: accent,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: .3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            session.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: preset.foreground(theme.brightness),
                            ),
                          ),
                          Text(
                            '${listeningStatusLabel(session, nowMs)} · $who',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: preset.foregroundMuted(theme.brightness),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: widget.onOpen,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(72, 40),
                      ),
                      child: Text(partnerListening ? 'Join' : 'Open'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
