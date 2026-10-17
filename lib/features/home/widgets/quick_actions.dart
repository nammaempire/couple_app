import 'package:flutter/material.dart';

/// A row of round shortcut buttons under the Home header.
class QuickActions extends StatelessWidget {
  const QuickActions({super.key, required this.actions});

  final List<QuickAction> actions;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [for (final action in actions) _QuickActionButton(action)],
    );
  }
}

class QuickAction {
  const QuickAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton(this.action);

  final QuickAction action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = action.onPressed != null;

    return Semantics(
      button: true,
      label: action.label,
      child: InkWell(
        onTap: action.onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.secondaryContainer.withValues(
                    alpha: enabled ? 1 : .4,
                  ),
                ),
                child: Icon(
                  action.icon,
                  color: theme.colorScheme.onSecondaryContainer.withValues(
                    alpha: enabled ? 1 : .5,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(action.label, style: theme.textTheme.labelMedium),
            ],
          ),
        ),
      ),
    );
  }
}
