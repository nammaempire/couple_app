import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:couple_app/core/services/voice_playback.dart';
import 'package:couple_app/core/utils/duration_format.dart';

/// Plays any voice recording by URL (a chat message, a love letter, or a
/// local file:// preview) through the shared [VoicePlayback].
class VoiceClipPlayer extends StatelessWidget {
  const VoiceClipPlayer({
    super.key,
    required this.clipId,
    required this.url,
    required this.color,
    this.duration,
    this.maxWidth = 220,
  });

  /// Unique per clip, so only one plays at a time.
  final String clipId;
  final String? url;
  final Duration? duration;
  final Color color;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final playback = VoicePlayback.instance;
    final message = (id: clipId, mediaUrl: url, duration: duration);

    return ListenableBuilder(
      listenable: playback,
      builder: (context, _) {
        final isCurrent = playback.isCurrent(message.id);
        final playing = isCurrent && playback.playing;
        final loading = isCurrent && playback.loading && !playing;

        final total =
            (isCurrent ? playback.total : null) ??
            message.duration ??
            Duration.zero;
        final position = isCurrent ? playback.position : Duration.zero;
        final progress = total.inMilliseconds == 0
            ? 0.0
            : (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);

        final shown = isCurrent && position > Duration.zero ? position : total;

        // Fits inside the bubble (75% of the screen, minus its padding) on
        // narrow phones.
        final width = math.min(
          maxWidth,
          MediaQuery.sizeOf(context).width * .75 - 24,
        );

        return SizedBox(
          width: width,
          child: Row(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: loading
                    ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: color,
                        ),
                      )
                    : IconButton(
                        padding: EdgeInsets.zero,
                        tooltip: playing ? 'Pause' : 'Play voice message',
                        icon: Icon(
                          playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: color,
                          size: 30,
                        ),
                        onPressed: message.mediaUrl == null
                            ? null
                            : () async {
                                try {
                                  await playback.toggle(
                                    message.id,
                                    message.mediaUrl!,
                                  );
                                } catch (_) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Could not play this voice message.',
                                      ),
                                    ),
                                  );
                                }
                              },
                      ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    overlayShape: SliderComponentShape.noOverlay,
                    activeTrackColor: color,
                    inactiveTrackColor: color.withValues(alpha: .3),
                    thumbColor: color,
                  ),
                  child: Slider(
                    value: progress,
                    onChanged: isCurrent && total > Duration.zero
                        ? (v) => playback.seek(
                            message.id,
                            Duration(
                              milliseconds: (total.inMilliseconds * v).round(),
                            ),
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatDuration(shown),
                style: TextStyle(
                  color: color.withValues(alpha: .8),
                  fontSize: 12,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
