import 'package:flutter/material.dart';

import 'package:couple_app/features/plans/models/date_plan.dart';
import 'package:couple_app/features/plans/widgets/date_plan_hearts.dart';

/// What the "How did it go?" sheet returns.
typedef DatePlanRecap = ({int? rating, String reflection});

/// Quick "How did it go?" sheet when marking a date done: optional hearts
/// and a few words. Pops with a [DatePlanRecap], or null if dismissed.
class DatePlanDoneSheet extends StatefulWidget {
  const DatePlanDoneSheet({super.key, required this.plan});

  final DatePlan plan;

  @override
  State<DatePlanDoneSheet> createState() => _DatePlanDoneSheetState();
}

class _DatePlanDoneSheetState extends State<DatePlanDoneSheet> {
  late int? _rating = widget.plan.rating;
  late final _reflection = TextEditingController(text: widget.plan.reflection);

  @override
  void dispose() {
    _reflection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'How did it go?',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.plan.title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: DatePlanHearts(
                  rating: _rating,
                  size: 32,
                  onChanged: (r) => setState(() => _rating = r),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reflection,
                textCapitalization: TextCapitalization.sentences,
                minLines: 2,
                maxLines: 5,
                maxLength: DatePlan.maxReflection,
                decoration: const InputDecoration(
                  hintText: 'A favourite moment, a funny bit… (optional)',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Navigator.pop<DatePlanRecap>(context, (
                  rating: _rating,
                  reflection: _reflection.text.trim(),
                )),
                icon: const Icon(Icons.favorite),
                label: const Text('Save to done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
