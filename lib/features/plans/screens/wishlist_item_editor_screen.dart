import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/plans/data/wishlist_service.dart';
import 'package:couple_app/features/plans/models/wishlist_item.dart';
import 'package:couple_app/features/plans/models/wishlist_price.dart';
import 'package:couple_app/features/plans/providers/wishlist_providers.dart';
import 'package:couple_app/features/plans/widgets/soft_kit.dart';
import 'package:couple_app/features/plans/widgets/wishlist_item_card.dart';

/// Add or edit one of your own wishes.
class WishlistItemEditorScreen extends ConsumerStatefulWidget {
  const WishlistItemEditorScreen({super.key, this.item});

  /// Must be one of the signed-in user's own items, or null for a new one.
  final WishlistItem? item;

  @override
  ConsumerState<WishlistItemEditorScreen> createState() =>
      _WishlistItemEditorScreenState();
}

class _WishlistItemEditorScreenState
    extends ConsumerState<WishlistItemEditorScreen> {
  late final String _coupleId;
  late final String _myUid;
  late final WishlistService _service;

  final _formKey = GlobalKey<FormState>();
  late final WishlistItem? _original = widget.item;
  late final _title = TextEditingController(text: _original?.title ?? '');
  late final _url = TextEditingController(text: _original?.url ?? '');
  late final _price = TextEditingController(
    text: WishlistPrice.toInput(_original?.priceMinor),
  );
  late final _notes = TextEditingController(text: _original?.notes ?? '');
  late WishlistPriority _priority =
      _original?.priority ?? WishlistPriority.love;
  late WishlistOccasion _occasion = _original?.occasion ?? WishlistOccasion.any;
  bool _saving = false;

  bool get _isEditing => _original != null;

  @override
  void initState() {
    super.initState();
    _coupleId = ref.read(currentCoupleIdProvider);
    _myUid = ref.read(currentUidProvider);
    _service = ref.read(wishlistServiceProvider);
  }

  @override
  void dispose() {
    _title.dispose();
    _url.dispose();
    _price.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final price = WishlistPrice.parse(_price.text).minor;
    final base =
        _original ?? WishlistItem(id: '', title: '', createdBy: _myUid);
    final item = base.copyWith(
      title: _title.text,
      notes: _notes.text,
      url: WishlistItem.normalizeUrl(_url.text),
      priceMinor: price,
      clearPrice: price == null,
      priority: _priority,
      occasion: _occasion,
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
        title: const Text('Delete this wish?'),
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
    final currency =
        ref.watch(coupleProvider).value?.currency ?? Couple.defaultCurrency;
    final partnerName = ref.watch(partnerNameProvider);

    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEditing ? 'Edit wish' : 'New wish'),
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
                  emoji: _priority.emoji,
                  preset: WishlistLook.presetFor(_priority),
                  text: 'Drop a hint, so the perfect gift finds you.',
                ),
              TextFormField(
                controller: _title,
                autofocus: !_isEditing,
                textCapitalization: TextCapitalization.sentences,
                maxLength: WishlistItem.maxTitleLength,
                decoration: const InputDecoration(
                  labelText: 'What would you like?',
                  hintText: 'e.g. A film camera',
                  counterText: '',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Add a title' : null,
              ),
              const SizedBox(height: 20),
              const SoftFieldLabel('How much do you want it?'),
              SegmentedButton<WishlistPriority>(
                segments: [
                  for (final p in WishlistPriority.values)
                    ButtonSegment(
                      value: p,
                      label: Text(p.label),
                      icon: Text(p.emoji),
                    ),
                ],
                selected: {_priority},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _priority = s.first),
              ),
              const SizedBox(height: 20),
              const SoftFieldLabel('Good for'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final o in WishlistOccasion.values)
                    ChoiceChip(
                      label: Text('${o.emoji} ${o.label}'),
                      selected: _occasion == o,
                      onSelected: (_) => setState(() => _occasion = o),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: InputDecoration(
                  labelText: 'Price (optional)',
                  prefixIcon: const Icon(Icons.sell_outlined),
                  prefixText: '${WishlistPrice.symbol(currency)} ',
                ),
                validator: (v) => WishlistPrice.parse(v ?? '').isValid
                    ? null
                    : 'Enter an amount up to '
                          '${WishlistPrice.format(WishlistPrice.maxMinor, currency)}',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _url,
                keyboardType: TextInputType.url,
                autocorrect: false,
                maxLength: WishlistItem.maxUrlLength,
                decoration: const InputDecoration(
                  labelText: 'Link (optional)',
                  hintText: 'Paste a shop link',
                  prefixIcon: Icon(Icons.link),
                  counterText: '',
                ),
                validator: (v) =>
                    WishlistItem.isValidUrl(WishlistItem.normalizeUrl(v ?? ''))
                    ? null
                    : 'That doesn\'t look like a web link',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                textCapitalization: TextCapitalization.sentences,
                minLines: 2,
                maxLines: 6,
                maxLength: WishlistItem.maxNotesLength,
                decoration: InputDecoration(
                  labelText: 'Notes (optional)',
                  hintText:
                      'Size, colour, the one you mean, so $partnerName '
                      'gets it right',
                  hintMaxLines: 2,
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
