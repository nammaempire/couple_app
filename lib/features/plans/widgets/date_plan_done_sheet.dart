import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/plans/models/date_plan.dart';
import 'package:couple_app/features/plans/widgets/date_plan_hearts.dart';
import 'package:couple_app/features/plans/widgets/soft_kit.dart';

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
    final b = theme.brightness;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SheetGradientHeader(
                preset: GradientPreset.blush,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'How did it go?',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: GradientPreset.blush.foreground(b),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.plan.title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: GradientPreset.blush.foregroundMuted(b),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: DatePlanHearts(
                        rating: _rating,
                        size: 32,
                        onChanged: (r) => setState(() => _rating = r),
                      ),
                    ),
                  ],
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
                style: FilledButton.styleFrom(shape: const StadiumBorder()),
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
