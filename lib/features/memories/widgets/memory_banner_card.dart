import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/floating_hearts.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/plans/widgets/soft_kit.dart';

/// A wide, softly drifting gradient card with three lines of text, used for
/// "On this day". A photo, when there is one, fills it under a scrim.
class MemoryBannerCard extends StatelessWidget {
  const MemoryBannerCard({
    super.key,
    required this.imageUrl,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.emoji = '📸',
    this.preset = GradientPreset.sunset,
  });

  final String? imageUrl;
  final String eyebrow;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Shown large when there is no photo.
  final String emoji;
  final GradientPreset preset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    final photo = imageUrl != null;
    final fg = photo ? Colors.white : preset.foreground(b);
    final fgMuted = photo
        ? Colors.white.withValues(alpha: .85)
        : preset.foregroundMuted(b);
    final eyebrowColor = photo
        ? Colors.white.withValues(alpha: .85)
        : presetAccentText(preset, b);

    return AnimatedGradientCard(
      preset: preset,
      onTap: onTap,
      radius: 24,
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: 150,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (photo) ...[
              CachedNetworkImage(imageUrl: imageUrl!, fit: BoxFit.cover),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x14000000), Color(0xBF000000)],
                  ),
                ),
              ),
            ] else ...[
              RepaintBoundary(
                child: FloatingHearts(
                  count: 8,
                  seed: 11,
                  color: Colors.white,
                  opacity: preset.isDarkIn(b) ? .35 : .6,
                ),
              ),
              Positioned(
                right: 18,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Container(
                    width: 76,
                    height: 76,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(
                        alpha: preset.isDarkIn(b) ? .12 : .55,
                      ),
                    ),
                    child: Text(emoji, style: const TextStyle(fontSize: 40)),
                  ),
                ),
              ),
            ],
            Positioned(
              left: 20,
              right: photo ? 20 : 110,
              bottom: 18,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    eyebrow,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: eyebrowColor,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(color: fgMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
