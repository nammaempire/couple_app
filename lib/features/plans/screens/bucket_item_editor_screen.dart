import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/plans/data/bucket_list_service.dart';
import 'package:couple_app/features/plans/models/bucket_item.dart';
import 'package:couple_app/features/plans/providers/bucket_list_providers.dart';
import 'package:couple_app/features/plans/widgets/soft_kit.dart';
import 'package:couple_app/features/plans/widgets/bucket_item_tile.dart';

/// Add or edit a bucket-list item, with notes and a target year.
///
/// [item] is an existing item, an unsaved draft (empty id) from the quick
/// add sheet, or null for a blank one.
class BucketItemEditorScreen extends ConsumerStatefulWidget {
  const BucketItemEditorScreen({super.key, this.item});

  final BucketItem? item;

  @override
  ConsumerState<BucketItemEditorScreen> createState() =>
      _BucketItemEditorScreenState();
}

class _BucketItemEditorScreenState
    extends ConsumerState<BucketItemEditorScreen> {
  late final String _coupleId;
  late final String _myUid;
  late final BucketListService _service;

  final _formKey = GlobalKey<FormState>();
  late final BucketItem? _original = widget.item;
  late final _title = TextEditingController(text: _original?.title ?? '');
  late final _notes = TextEditingController(text: _original?.notes ?? '');
  late BucketCategory _category = _original?.category ?? BucketCategory.travel;
  late int? _targetYear = _original?.targetYear;
  bool _saving = false;

  bool get _isEditing => (_original?.id ?? '').isNotEmpty;

  @override
  void initState() {
    super.initState();
    _coupleId = ref.read(currentCoupleIdProvider);
    _myUid = ref.read(currentUidProvider);
    _service = ref.read(bucketListServiceProvider);
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  List<int> get _yearChoices {
    final now = DateTime.now().year;
    final years = [for (var y = now; y <= now + 10; y++) y];
    final current = _targetYear;
    if (current != null && !years.contains(current)) years.insert(0, current);
    return years;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final base = _original ?? BucketItem(id: '', title: '', createdBy: _myUid);
    final item = base.copyWith(
      title: _title.text,
      notes: _notes.text,
      category: _category,
      targetYear: _targetYear,
      clearTargetYear: _targetYear == null,
    );

    try {
      await _service.save(_coupleId, item);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      context.showSnackMessage('Could not save. Check your connection.');
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this dream?'),
        content: const Text('This removes it for both of you.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await _service.delete(_coupleId, _original!.id);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      context.showSnackMessage('Could not delete. Check your connection.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEditing ? 'Edit dream' : 'New dream'),
          leading: IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: _saving ? null : () => Navigator.pop(context),
          ),
          actions: [
            if (_isEditing)
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: _saving ? null : _delete,
              ),
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
              if (!_isEditing)
                EditorHeaderStrip(
                  emoji: _category.emoji,
                  preset: BucketLook.presetFor(_category),
                  text: 'Someday starts with writing it down.',
                ),
              TextFormField(
                controller: _title,
                autofocus: !_isEditing && _title.text.isEmpty,
                textCapitalization: TextCapitalization.sentences,
                maxLength: BucketItem.maxTitleLength,
                decoration: const InputDecoration(
                  labelText: 'What do you want to do?',
                  hintText: 'e.g. Learn to salsa together',
                  counterText: '',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Add a title' : null,
              ),
              const SizedBox(height: 20),
              const SoftFieldLabel('Category'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in BucketCategory.values)
                    ChoiceChip(
                      label: Text('${c.emoji} ${c.label}'),
                      selected: _category == c,
                      onSelected: (_) => setState(() => _category = c),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<int?>(
                initialValue: _targetYear,
                decoration: const InputDecoration(
                  labelText: 'Hoping to do it by',
                  prefixIcon: Icon(Icons.flag_outlined),
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Someday'),
                  ),
                  for (final y in _yearChoices)
                    DropdownMenuItem<int?>(value: y, child: Text('$y')),
                ],
                onChanged: (y) => setState(() => _targetYear = y),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notes,
                textCapitalization: TextCapitalization.sentences,
                minLines: 3,
                maxLines: 8,
                maxLength: BucketItem.maxNotesLength,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  hintText: 'Ideas, links, how you want it to feel',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
