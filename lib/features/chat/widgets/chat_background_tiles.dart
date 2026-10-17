import 'package:flutter/material.dart';

import 'package:couple_app/features/chat/models/chat_look.dart';
import 'package:couple_app/features/chat/widgets/chat_background_layer.dart';
import 'package:couple_app/features/chat/widgets/chat_palette.dart';
import 'package:couple_app/features/chat/widgets/chat_patterns.dart';

/// A grid of background choices: none, each built-in pattern, and a photo.
/// Each tile is drawn with the real background layer in the chat colour.
class ChatBackgroundTiles extends StatelessWidget {
  const ChatBackgroundTiles({
    super.key,
    required this.look,
    required this.onNone,
    required this.onPattern,
    required this.onPhoto,
  });

  /// The look being edited; tiles use its colour and mark its background.
  final ChatLook look;
  final VoidCallback onNone;
  final ValueChanged<String> onPattern;

  /// Tapped the photo tile, to choose (or change) a photo.
  final VoidCallback onPhoto;

  @override
  Widget build(BuildContext context) {
    final bg = look.background;
    final hasPattern = bg.isPattern && ChatPatterns.isKnown(bg.patternId);
    final tiles = <Widget>[
      _Tile(
        key: const ValueKey('bg-none'),
        label: 'None',
        selected: !bg.isPhoto && !hasPattern,
        onTap: onNone,
        child: const ChatBackgroundLayer(background: ChatBackground.none),
      ),
      for (final pattern in ChatPatterns.all)
        _Tile(
          key: ValueKey('bg-${pattern.id}'),
          label: pattern.label,
          selected: hasPattern && bg.patternId == pattern.id,
          onTap: () => onPattern(pattern.id),
          child: ChatBackgroundLayer(
            background: ChatBackground(
              kind: ChatBackgroundKind.pattern,
              patternId: pattern.id,
            ),
          ),
        ),
      _Tile(
        key: const ValueKey('bg-photo'),
        label: 'Photo',
        selected: bg.isPhoto,
        onTap: onPhoto,
        child: bg.isPhoto
            ? ChatBackgroundLayer(background: bg)
            : const _AddPhoto(),
      ),
    ];

    return Theme(
      data: ChatPalette.applyTo(
        Theme.of(context),
        ChatLook(colorValue: look.colorValue),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const spacing = 10.0;
          final columns = constraints.maxWidth >= 520 ? 6 : 4;
          final width =
              (constraints.maxWidth - spacing * (columns - 1)) / columns;
          return Wrap(
            spacing: spacing,
            runSpacing: 14,
            children: [
              for (final tile in tiles) SizedBox(width: width, child: tile),
            ],
          );
        },
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(16);

    return Semantics(
      button: true,
      selected: selected,
      label: '$label background',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: .8,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: selected ? scheme.primary : scheme.outlineVariant,
                    width: selected ? 2.5 : 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: radius,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      child,
                      if (selected)
                        Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: const EdgeInsets.all(5),
                            child: CircleAvatar(
                              radius: 10,
                              backgroundColor: scheme.primary,
                              child: Icon(
                                Icons.check_rounded,
                                size: 14,
                                color: scheme.onPrimary,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w700 : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddPhoto extends StatelessWidget {
  const _AddPhoto();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Icon(
        Icons.add_photo_alternate_outlined,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}
