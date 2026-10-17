import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/plans/data/bucket_list_service.dart';
import 'package:couple_app/features/plans/models/bucket_item.dart';
import 'package:couple_app/features/plans/providers/bucket_list_providers.dart';

/// A bottom sheet to add a bucket-list item with just a title and category.
///
/// Pops with null once saved, or with an unsaved draft when the user asks
/// for more details, so the caller can open the full editor.
class BucketQuickAddSheet extends ConsumerStatefulWidget {
  const BucketQuickAddSheet({super.key, this.initialCategory});

  final BucketCategory? initialCategory;

  @override
  ConsumerState<BucketQuickAddSheet> createState() =>
      _BucketQuickAddSheetState();
}

class _BucketQuickAddSheetState extends ConsumerState<BucketQuickAddSheet> {
  late final String _coupleId;
  late final String _myUid;
  late final BucketListService _service;

  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  late BucketCategory _category =
      widget.initialCategory ?? BucketCategory.travel;
  bool _saving = false;

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
    super.dispose();
  }

  BucketItem get _draft => BucketItem(
    id: '',
    title: _title.text,
    category: _category,
    createdBy: _myUid,
  );

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await _service.save(_coupleId, _draft);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      context.showSnackMessage('Could not save. Check your connection.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: !_saving,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add to your bucket list',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Big or small, something you want to do together.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _title,
                autofocus: true,
                enabled: !_saving,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                maxLength: BucketItem.maxTitleLength,
                decoration: const InputDecoration(
                  hintText: 'e.g. See the northern lights',
                  counterText: '',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Add a title' : null,
                onFieldSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in BucketCategory.values)
                    ChoiceChip(
                      label: Text('${c.emoji} ${c.label}'),
                      selected: _category == c,
                      onSelected: _saving
                          ? null
                          : (_) => setState(() => _category = c),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _saving
                        ? null
                        : () => Navigator.pop(context, _draft),
                    icon: const Icon(Icons.tune),
                    label: const Text('More details'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(112, 48),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Add'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
