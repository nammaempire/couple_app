import 'package:flutter/material.dart';

import 'package:couple_app/features/avatar/models/avatar_config.dart';

/// A wrap of colour circles; the [selected] one gets a ring and a tick.
class AvatarSwatchPicker extends StatelessWidget {
  const AvatarSwatchPicker({
    super.key,
    required this.part,
    required this.swatches,
    required this.selected,
    required this.onSelected,
    this.size = 38,
  });

  /// Names the part in widget keys (`avatar-swatch-<part>-<id>`).
  final String part;
  final List<AvatarSwatch> swatches;
  final String selected;
  final ValueChanged<String> onSelected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final swatch in swatches)
          Tooltip(
            message: swatch.label,
            child: Semantics(
              button: true,
              selected: swatch.id == selected,
              label: swatch.label,
              excludeSemantics: true,
              child: InkResponse(
                key: ValueKey('avatar-swatch-$part-${swatch.id}'),
                onTap: () => onSelected(swatch.id),
                radius: size / 2 + 4,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: size,
                  height: size,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: swatch.id == selected
                          ? scheme.primary
                          : scheme.outlineVariant,
                      width: swatch.id == selected ? 2.5 : 1,
                    ),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: swatch.color,
                    ),
                    child: swatch.id == selected
                        ? Icon(
                            Icons.check,
                            size: size * .45,
                            color: swatch.color.computeLuminance() > .5
                                ? Colors.black87
                                : Colors.white,
                          )
                        : null,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
