import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/music/data/media_shelf.dart';
import 'package:couple_app/features/music/data/music_service.dart';
import 'package:couple_app/features/music/models/listening_session.dart';
import 'package:couple_app/features/music/models/song.dart';
import 'package:couple_app/features/music/providers/music_providers.dart';
import 'package:couple_app/features/music/screens/listen_together_screen.dart';
import 'package:couple_app/features/music/widgets/moment_look.dart';
import 'package:couple_app/features/music/widgets/on_gradient_theme.dart';
import 'package:couple_app/features/music/widgets/song_artwork.dart';

/// A slim "listening together" / "watching together" bar above the
/// shell's navigation, shown on every tab while a session is live. With
/// both a music and a watch session live, the one changed most recently
/// wins. Tap to open the player.
///
/// The player opens as a full page over the shell, so the banner never
/// shows on top of it.
class ListeningBanner extends ConsumerWidget {
  const ListeningBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Checked again on every rebuild: a forgotten session goes stale.
    final now = ref.read(musicServiceProvider).clock.nowMs();
    ListeningSession? active(MediaShelf shelf) {
      final s = ref.watch(liveMediaSessionProvider(shelf));
      return s != null && s.isActive(now) ? s : null;
    }

    final music = active(MediaShelf.songs);
    final video = active(MediaShelf.videos);
    final (session, shelf) = switch ((music, video)) {
      (final m?, final v?) =>
        v.at > m.at ? (v, MediaShelf.videos) : (m, MediaShelf.songs),
      (final m?, null) => (m, MediaShelf.songs),
      (null, final v?) => (v, MediaShelf.videos),
      (null, null) => (null, MediaShelf.songs),
    };
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      alignment: Alignment.bottomCenter,
      child: session != null
          ? _Bar(session: session, shelf: shelf)
          : const SizedBox(width: double.infinity),
    );
  }
}

class _Bar extends ConsumerWidget {
  const _Bar({required this.session, required this.shelf});

  final ListeningSession session;
  final MediaShelf shelf;

  Future<void> _togglePlay(BuildContext context, WidgetRef ref) async {
    final service = ref.read(mediaServiceProvider(shelf));
    try {
      await service.setStatus(
        coupleId: ref.read(currentCoupleIdProvider),
        uid: ref.read(currentUidProvider),
        status: session.status == ListeningStatus.paused
            ? ListeningStatus.playing
            : ListeningStatus.paused,
      );
    } on ListeningException catch (e) {
      if (context.mounted) context.showSnackMessage(e.message);
    } catch (_) {
      if (context.mounted) {
        context.showSnackMessage('Could not sync. Check your connection.');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final myUid = ref.watch(currentUidProvider);
    final partnerName = ref.watch(partnerNameProvider);
    final partnerUid = ref.watch(
      coupleProvider.select((c) => c.value?.partnerIdFor(myUid)),
    );
    final now = ref.read(musicServiceProvider).clock.nowMs();
    final partnerPlaying =
        partnerUid != null &&
        session.isListening(partnerUid, now) &&
        !session.isListening(myUid, now);
    final paused = session.status == ListeningStatus.paused;

    var moment = shelf == MediaShelf.videos
        ? SongMoment.movieNight
        : SongMoment.romantic;
    for (final s
        in ref.watch(mediaItemsProvider(shelf)).value ?? const <Song>[]) {
      if (s.id == session.songId && s.moment != SongMoment.other) {
        moment = s.moment;
      }
    }
    final preset = moment.preset;
    final fg = preset.foreground(theme.brightness);
    final accent = OnGradientTheme.ink(preset, theme.brightness);

    return AnimatedGradientCard(
      preset: preset,
      radius: 0,
      shadow: false,
      onTap: () => ListenTogetherScreen.open(context, shelf: shelf),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      child: OnGradientTheme(
        preset: preset,
        child: Row(
          children: [
            SongArtwork(
              url: session.thumbnailUrl,
              source: session.source,
              size: 36,
              radius: 8,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: partnerPlaying
                      ? [
                          TextSpan(
                            text: shelf == MediaShelf.videos
                                ? '$partnerName is watching '
                                : '$partnerName is playing ',
                          ),
                          TextSpan(
                            text: session.displayTitle,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(
                            text: ' — Join',
                            style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ]
                      : [
                          TextSpan(text: '${shelf.togetherTitle} · '),
                          TextSpan(
                            text: session.displayTitle,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(color: fg),
              ),
            ),
            if (session.playsInApp)
              IconButton(
                tooltip: paused ? 'Play for both' : 'Pause for both',
                visualDensity: VisualDensity.compact,
                color: fg,
                onPressed: () => _togglePlay(context, ref),
                icon: Icon(
                  paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Icon(Icons.headphones_outlined, size: 20, color: fg),
              ),
          ],
        ),
      ),
    );
  }
}
