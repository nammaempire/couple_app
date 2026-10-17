import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/features/plans/models/bucket_item.dart';

/// One bucket-list item with a round tick button.
class BucketItemTile extends StatelessWidget {
  const BucketItemTile({
    super.key,
    required this.item,
    required this.doneByName,
    required this.onToggle,
    required this.onTap,
    this.celebrate = false,
  });

  final BucketItem item;

  /// "you" or the partner's name, for done items.
  final String? doneByName;
  final VoidCallback onToggle;
  final VoidCallback onTap;

  /// Plays a small pop when the tile first appears (just ticked off).
  final bool celebrate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final overdue = item.isOverdue(DateTime.now());

    final details = <InlineSpan>[];
    void add(String text, {Color? color}) {
      if (details.isNotEmpty) details.add(const TextSpan(text: ' · '));
      details.add(
        TextSpan(
          text: text,
          style: color == null ? null : TextStyle(color: color),
        ),
      );
    }

    if (item.done) {
      final who = doneByName;
      final when = item.doneAt;
      add(
        [
          who == null ? 'Done' : 'Ticked off by $who',
          if (when != null) DateFormat.yMMMd().format(when),
        ].join(' · '),
      );
    } else {
      add('${item.category.emoji} ${item.category.label}');
      final year = item.targetYear;
      if (year != null) {
        add(
          overdue ? 'Hoped for $year' : 'By $year',
          color: overdue ? scheme.error : null,
        );
      }
    }

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.fromLTRB(8, 2, 16, 2),
      leading: _TickButton(
        done: item.done,
        celebrate: celebrate,
        onPressed: onToggle,
      ),
      title: Text(
        item.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: item.done
            ? TextStyle(
                color: scheme.onSurfaceVariant,
                decoration: TextDecoration.lineThrough,
                decorationColor: scheme.onSurfaceVariant.withValues(alpha: 0.5),
              )
            : null,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text.rich(TextSpan(children: details)),
          if (item.notes.isNotEmpty && !item.done)
            Text(
              item.notes,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _TickButton extends StatefulWidget {
  const _TickButton({
    required this.done,
    required this.celebrate,
    required this.onPressed,
  });

  final bool done;
  final bool celebrate;
  final VoidCallback onPressed;

  @override
  State<_TickButton> createState() => _TickButtonState();
}

class _TickButtonState extends State<_TickButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    if (widget.celebrate && widget.done) _pop.forward(from: 0);
  }

  @override
  void didUpdateWidget(_TickButton old) {
    super.didUpdateWidget(old);
    if (widget.done && !old.done) _pop.forward(from: 0);
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scale = CurvedAnimation(parent: _pop, curve: Curves.elasticOut);
    final ring = CurvedAnimation(parent: _pop, curve: Curves.easeOut);

    return Semantics(
      checked: widget.done,
      child: IconButton(
        tooltip: widget.done ? 'Mark as not done' : 'Tick it off',
        onPressed: widget.onPressed,
        icon: SizedBox(
          width: 32,
          height: 32,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // A soft ring that grows and fades as it is ticked.
              if (widget.done)
                AnimatedBuilder(
                  animation: ring,
                  builder: (context, _) => ring.value >= 1
                      ? const SizedBox.shrink()
                      : Container(
                          width: 28 + 20 * ring.value,
                          height: 28 + 20 * ring.value,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: scheme.primary.withValues(
                                alpha: 0.5 * (1 - ring.value),
                              ),
                              width: 2,
                            ),
                          ),
                        ),
                ),
              ScaleTransition(
                scale: widget.done
                    ? Tween(begin: 0.6, end: 1.0).animate(scale)
                    : const AlwaysStoppedAnimation(1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.done ? scheme.primary : Colors.transparent,
                    border: Border.all(
                      color: widget.done ? scheme.primary : scheme.outline,
                      width: 2,
                    ),
                  ),
                  child: widget.done
                      ? Icon(Icons.check, size: 18, color: scheme.onPrimary)
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
