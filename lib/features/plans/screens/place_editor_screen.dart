import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/plans/data/place_service.dart';
import 'package:couple_app/features/plans/models/place.dart';
import 'package:couple_app/features/plans/providers/place_providers.dart';
import 'package:couple_app/features/plans/widgets/place_rating_stars.dart';
import 'package:couple_app/features/together/widgets/event_picker_field.dart';
import 'package:couple_app/features/plans/widgets/soft_kit.dart';
import 'package:couple_app/features/plans/widgets/place_card.dart';

/// Add or edit a place.
class PlaceEditorScreen extends ConsumerStatefulWidget {
  const PlaceEditorScreen({super.key, this.place, this.initialStatus});

  final Place? place;

  /// For a new place: which tab it was added from.
  final PlaceStatus? initialStatus;

  @override
  ConsumerState<PlaceEditorScreen> createState() => _PlaceEditorScreenState();
}

class _PlaceEditorScreenState extends ConsumerState<PlaceEditorScreen> {
  late final String _coupleId;
  late final String _myUid;
  late final PlaceService _service;

  @override
  void initState() {
    super.initState();
    _coupleId = ref.read(currentCoupleIdProvider);
    _myUid = ref.read(currentUidProvider);
    _service = ref.read(placeServiceProvider);
  }

  final _formKey = GlobalKey<FormState>();

  late final Place? _original = widget.place;
  late final _name = TextEditingController(text: _original?.name ?? '');
  late final _area = TextEditingController(text: _original?.area ?? '');
  late final _mapsUrl = TextEditingController(text: _original?.mapsUrl ?? '');
  late final _notes = TextEditingController(text: _original?.notes ?? '');

  late PlaceCategory _category = _original?.category ?? PlaceCategory.cafe;
  late PlaceStatus _status =
      _original?.status ?? widget.initialStatus ?? PlaceStatus.wantToGo;
  late DateTime _visitedAt = _original?.visitedAt ?? _today();
  late int? _rating = _original?.rating;
  late bool _favourite = _original?.favourite ?? false;

  bool _saving = false;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void dispose() {
    _name.dispose();
    _area.dispose();
    _mapsUrl.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickVisited() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _visitedAt.isAfter(_today()) ? _today() : _visitedAt,
      firstDate: DateTime(1970),
      lastDate: _today(),
      helpText: 'When did you go?',
    );
    if (picked != null) setState(() => _visitedAt = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final been = _status == PlaceStatus.been;
    final place = Place(
      id: _original?.id ?? '',
      name: _name.text,
      area: _area.text,
      mapsUrl: _mapsUrl.text.trim(),
      category: _category,
      status: _status,
      rating: been ? _rating : null,
      visitedAt: been ? _visitedAt : null,
      notes: _notes.text,
      favourite: _favourite,
      // The creator never changes, even when the partner edits.
      createdBy: _original?.createdBy ?? _myUid,
    );

    setState(() => _saving = true);
    try {
      await _service.save(_coupleId, place);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      context.showSnackMessage('Could not save. Check your connection.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = _original != null;

    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(isEditing ? 'Edit place' : 'New place'),
          leading: IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: _saving ? null : () => Navigator.pop(context),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(minimumSize: const Size(72, 40)),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              if (!isEditing)
                EditorHeaderStrip(
                  emoji: _category.emoji,
                  preset: PlaceLook.presetFor(_category),
                  text: 'Pin a spot on your map of us.',
                ),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<PlaceStatus>(
                  segments: [
                    for (final s in PlaceStatus.values)
                      ButtonSegment(value: s, label: Text(s.label)),
                  ],
                  selected: {_status},
                  onSelectionChanged: (s) => setState(() => _status = s.first),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                autofocus: !isEditing,
                textCapitalization: TextCapitalization.words,
                maxLength: Place.maxName,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. Third Wave Coffee',
                  counterText: '',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Add a name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _area,
                textCapitalization: TextCapitalization.words,
                maxLength: Place.maxArea,
                decoration: const InputDecoration(
                  labelText: 'Area or address (optional)',
                  hintText: 'e.g. Indiranagar, Bengaluru',
                  prefixIcon: Icon(Icons.place_outlined),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 20),
              const SoftFieldLabel('Category'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in PlaceCategory.values)
                    ChoiceChip(
                      label: Text('${c.emoji} ${c.label}'),
                      selected: _category == c,
                      onSelected: (_) => setState(() => _category = c),
                    ),
                ],
              ),
              if (_status == PlaceStatus.been) ...[
                const SizedBox(height: 20),
                EventPickerField(
                  label: 'When you went',
                  icon: Icons.event_available_outlined,
                  value: DateFormat.yMMMEd().format(_visitedAt),
                  onTap: _pickVisited,
                ),
                const SizedBox(height: 12),
                const SoftFieldLabel('Your rating'),
                PlaceRatingStars(
                  rating: _rating,
                  size: 30,
                  onChanged: (r) => setState(() => _rating = r),
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: _mapsUrl,
                keyboardType: TextInputType.url,
                maxLength: Place.maxMapsUrl,
                decoration: const InputDecoration(
                  labelText: 'Maps link (optional)',
                  hintText: 'Paste a Google Maps link',
                  helperText: 'Without one, we search Maps for the name.',
                  prefixIcon: Icon(Icons.link),
                  counterText: '',
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty || Place.isWebUrl(t)) return null;
                  return 'Use a link starting with http:// or https://';
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                textCapitalization: TextCapitalization.sentences,
                minLines: 2,
                maxLines: 6,
                maxLength: Place.maxNotes,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  hintText: 'What to order, best time to go…',
                  prefixIcon: Icon(Icons.notes),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: Icon(
                  _favourite ? Icons.favorite : Icons.favorite_border,
                  color: _favourite ? theme.colorScheme.primary : null,
                ),
                title: const Text('Favourite'),
                value: _favourite,
                onChanged: (v) => setState(() => _favourite = v),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
