import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:couple_app/features/chat/models/chat_look.dart';
import 'package:couple_app/features/chat/widgets/chat_patterns.dart';

/// What sits behind the messages: the plain chat colour, a built-in
/// pattern or a (dimmed, optionally blurred) photo. Fills its box.
///
/// A photo that is still loading, or fails to load, shows the plain colour.
class ChatBackgroundLayer extends StatelessWidget {
  const ChatBackgroundLayer({super.key, required this.background});

  final ChatBackground background;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.scaffoldBackgroundColor;
    final bg = background;

    if (bg.isPhoto) {
      return ColoredBox(
        color: base,
        child: SizedBox.expand(
          child: CachedNetworkImage(
            imageUrl: bg.photoUrl!,
            fadeInDuration: const Duration(milliseconds: 200),
            placeholder: (_, _) => const SizedBox.expand(),
            errorWidget: (_, _, _) => const SizedBox.expand(),
            imageBuilder: (_, image) =>
                _Photo(image: image, blur: bg.blur, dim: bg.dim),
          ),
        ),
      );
    }

    if (bg.isPattern && ChatPatterns.isKnown(bg.patternId)) {
      return RepaintBoundary(
        child: CustomPaint(
          painter: ChatPatternPainter(
            patternId: bg.patternId!,
            scheme: theme.colorScheme,
            background: base,
          ),
          child: const SizedBox.expand(),
        ),
      );
    }

    return ColoredBox(color: base, child: const SizedBox.expand());
  }
}

class _Photo extends StatelessWidget {
  const _Photo({required this.image, required this.blur, required this.dim});

  final ImageProvider image;
  final double blur;
  final double dim;

  @override
  Widget build(BuildContext context) {
    Widget photo = Image(image: image, fit: BoxFit.cover);
    if (blur > 0) {
      photo = ImageFiltered(
        imageFilter: ImageFilter.blur(
          sigmaX: blur,
          sigmaY: blur,
          tileMode: TileMode.clamp,
        ),
        child: photo,
      );
    }
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          photo,
          if (dim > 0) ColoredBox(color: Colors.black.withValues(alpha: dim)),
        ],
      ),
    );
  }
}
