import 'package:flutter/material.dart';

import 'package:couple_app/features/avatar/models/avatar_config.dart';
import 'package:couple_app/features/avatar/widgets/avatar_view.dart';

/// A builder tile previewing [config] (the current avatar with one option
/// applied), with its [label] underneath.
class AvatarOptionTile extends StatelessWidget {
  const AvatarOptionTile({
    super.key,
    required this.config,
    required this.label,
    required this.selected,
    required this.onTap,
    this.expression = AvatarExpression.happy,
    this.showShoulders = false,
  });

  final AvatarConfig config;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final AvatarExpression expression;
  final bool showShoulders;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected
            ? scheme.primaryContainer.withValues(alpha: .55)
            : scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? scheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
            child: Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) => Center(
                      child: AvatarView(
                        config: config,
                        expression: expression,
                        size: box.biggest.shortestSide,
                        showShoulders: showShoulders,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
