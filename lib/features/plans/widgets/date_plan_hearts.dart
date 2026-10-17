import 'package:flutter/material.dart';

/// One to five hearts. Tappable when [onChanged] is set: tapping the
/// current rating again clears it.
class DatePlanHearts extends StatelessWidget {
  const DatePlanHearts({
    super.key,
    required this.rating,
    this.onChanged,
    this.size = 18,
  });

  final int? rating;
  final ValueChanged<int?>? onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final value = rating ?? 0;
    final onChanged = this.onChanged;

    return Semantics(
      label: value == 0 ? 'No rating' : '$value of 5 hearts',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            if (onChanged == null)
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Icon(
                  i <= value ? Icons.favorite : Icons.favorite_border,
                  size: size,
                  color: i <= value ? scheme.primary : scheme.outlineVariant,
                ),
              )
            else
              IconButton(
                tooltip: '$i of 5',
                visualDensity: VisualDensity.compact,
                onPressed: () => onChanged(i == value ? null : i),
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, animation) =>
                      ScaleTransition(scale: animation, child: child),
                  child: Icon(
                    i <= value ? Icons.favorite : Icons.favorite_border,
                    key: ValueKey(i <= value),
                    size: size,
                    color: i <= value ? scheme.primary : scheme.outline,
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
