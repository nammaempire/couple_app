import 'package:flutter/material.dart';

import 'package:couple_app/core/theme/app_theme.dart';

/// One chat colour on offer. A null [value] is the app's default rose.
typedef ChatSwatch = ({int? value, String label});

/// Round colour swatches for the chat, each showing the bubble colour it
/// produces in the current brightness.
class ChatColorPicker extends StatelessWidget {
  const ChatColorPicker({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  /// The chosen ARGB, or null for the default.
  final int? selected;
  final ValueChanged<int?> onSelected;

  /// Curated seeds that make pleasant Material 3 schemes in light and dark.
  static const swatches = <ChatSwatch>[
    (value: null, label: 'Default'),
    (value: 0xFFF4845F, label: 'Coral'),
    (value: 0xFFF2A541, label: 'Apricot'),
    (value: 0xFF7FA77A, label: 'Sage'),
    (value: 0xFF2A9D8F, label: 'Teal'),
    (value: 0xFF3A86C8, label: 'Ocean'),
    (value: 0xFF5C6BC0, label: 'Indigo'),
    (value: 0xFF9575CD, label: 'Lavender'),
    (value: 0xFF8E4585, label: 'Plum'),
    (value: 0xFFC2185B, label: 'Berry'),
    (value: 0xFF8D6E63, label: 'Cocoa'),
    (value: 0xFF607D8B, label: 'Slate'),
  ];

  /// The label for [value], or "Custom" for a colour not offered here.
  static String labelFor(int? value) {
    for (final s in swatches) {
      if (s.value == value) return s.label;
    }
    return 'Custom';
  }

  static final _primaries = <(int, Brightness), Color>{};

  /// The primary colour a scheme seeded with [seed] gets: what my bubbles
  /// will actually look like.
  static Color _primaryFor(int seed, Brightness brightness) =>
      _primaries.putIfAbsent(
        (seed, brightness),
        () => ColorScheme.fromSeed(
          seedColor: Color(seed),
          brightness: brightness,
        ).primary,
      );

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final swatch in swatches)
          _Swatch(
            key: ValueKey('swatch-${swatch.label}'),
            label: swatch.label,
            color: _primaryFor(
              swatch.value ?? AppTheme.seed.toARGB32(),
              brightness,
            ),
            selected: swatch.value == selected,
            onTap: () => onSelected(swatch.value),
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    super.key,
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black87;

    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        label: '$label colour',
        child: InkResponse(
          onTap: onTap,
          radius: 28,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 44,
            height: 44,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? scheme.onSurface : Colors.transparent,
                width: 2,
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: .5),
                ),
              ),
              child: AnimatedOpacity(
                opacity: selected ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: Icon(Icons.check_rounded, size: 20, color: onColor),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
