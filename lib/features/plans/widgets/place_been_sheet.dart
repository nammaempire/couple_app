import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/features/plans/models/place.dart';
import 'package:couple_app/features/plans/widgets/place_rating_stars.dart';
import 'package:couple_app/features/together/widgets/event_picker_field.dart';

/// What the "We've been" sheet returns.
typedef PlaceVisit = ({DateTime visitedAt, int? rating, String notes});

/// Quick sheet to mark a place as visited: the day, an optional rating and
/// a note. Pops with a [PlaceVisit], or null if dismissed.
class PlaceBeenSheet extends StatefulWidget {
  const PlaceBeenSheet({super.key, required this.place});

  final Place place;

  @override
  State<PlaceBeenSheet> createState() => _PlaceBeenSheetState();
}

class _PlaceBeenSheetState extends State<PlaceBeenSheet> {
  late DateTime _day = _today();
  late int? _rating = widget.place.rating;
  late final _notes = TextEditingController(text: widget.place.notes);

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(1970),
      lastDate: _today(),
      helpText: 'When did you go?',
    );
    if (picked != null) setState(() => _day = picked);
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
                'You went to ${widget.place.name}',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              EventPickerField(
                label: 'When',
                icon: Icons.event_outlined,
                value: DateFormat.yMMMEd().format(_day),
                onTap: _pickDay,
              ),
              const SizedBox(height: 12),
              Text('How was it?', style: theme.textTheme.titleSmall),
              PlaceRatingStars(
                rating: _rating,
                size: 30,
                onChanged: (r) => setState(() => _rating = r),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _notes,
                textCapitalization: TextCapitalization.sentences,
                minLines: 2,
                maxLines: 5,
                maxLength: Place.maxNotes,
                decoration: const InputDecoration(
                  hintText: 'What to order, where to sit… (optional)',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Navigator.pop<PlaceVisit>(context, (
                  visitedAt: _day,
                  rating: _rating,
                  notes: _notes.text.trim(),
                )),
                icon: const Icon(Icons.check),
                label: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
