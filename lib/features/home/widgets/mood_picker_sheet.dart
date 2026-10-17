import 'package:flutter/material.dart';

import 'package:couple_app/features/home/models/mood.dart';

/// Bottom sheet for picking a mood and an optional short note. Pops with
/// a `({Mood mood, String note})` record when shared.
class MoodPickerSheet extends StatefulWidget {
  const MoodPickerSheet({super.key, required this.current});

  final MoodEntry? current;

  @override
  State<MoodPickerSheet> createState() => _MoodPickerSheetState();
}

class _MoodPickerSheetState extends State<MoodPickerSheet> {
  late Mood _selected = widget.current?.mood ?? Mood.happy;
  late final _note = TextEditingController(text: widget.current?.note ?? '');

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How are you feeling?', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: Mood.values.map((mood) {
              final isSelected = mood == _selected;
              return GestureDetector(
                onTap: () => setState(() => _selected = mood),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? mood.color.withValues(alpha: .35)
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: isSelected ? mood.color : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(mood.emoji, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      Text(mood.label),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _note,
            maxLength: 60,
            decoration: const InputDecoration(
              hintText: 'Add a word or two (optional)',
              counterText: '',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, (mood: _selected, note: _note.text)),
            child: const Text('Share it'),
          ),
        ],
      ),
    );
  }
}
