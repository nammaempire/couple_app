import 'package:flutter/material.dart';

/// One to five stars for a place. Tappable when [onChanged] is set: tapping
/// the current rating again clears it.
class PlaceRatingStars extends StatelessWidget {
  const PlaceRatingStars({
    super.key,
    required this.rating,
    this.onChanged,
    this.size = 16,
  });

  final int? rating;
  final ValueChanged<int?>? onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final value = rating ?? 0;
    final onChanged = this.onChanged;

    Icon star(int i) => Icon(
      i <= value ? Icons.star_rounded : Icons.star_outline_rounded,
      size: size,
      color: i <= value ? scheme.tertiary : scheme.outline,
    );

    return Semantics(
      label: value == 0 ? 'Not rated' : 'Rated $value of 5',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            if (onChanged == null)
              star(i)
            else
              IconButton(
                tooltip: '$i of 5',
                visualDensity: VisualDensity.compact,
                onPressed: () => onChanged(i == value ? null : i),
                icon: star(i),
              ),
        ],
      ),
    );
  }
}
