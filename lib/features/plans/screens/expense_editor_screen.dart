import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/core/widgets/empty_state.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/plans/data/expense_service.dart';
import 'package:couple_app/features/plans/models/expense.dart';
import 'package:couple_app/features/plans/models/expense_math.dart';
import 'package:couple_app/features/plans/providers/expense_providers.dart';
import 'package:couple_app/features/plans/widgets/expense_split_preview.dart';

/// Which custom share was filled in automatically from the other one.
enum _AutoShare { mine, theirs }

/// Add or edit a shared expense.
class ExpenseEditorScreen extends ConsumerStatefulWidget {
  const ExpenseEditorScreen({super.key, this.expense});

  /// The expense to edit, or null to add a new one.
  final Expense? expense;

  @override
  ConsumerState<ExpenseEditorScreen> createState() =>
      _ExpenseEditorScreenState();
}

class _ExpenseEditorScreenState extends ConsumerState<ExpenseEditorScreen> {
  late final String _coupleId;
  late final String _myUid;
  late final ExpenseService _service;

  final _formKey = GlobalKey<FormState>();

  late final Expense? _original = widget.expense;
  late final _amount = TextEditingController(
    text: _original == null ? '' : ExpenseMath.toInput(_original.amountMinor),
  );
  late final _title = TextEditingController(text: _original?.title ?? '');
  late final _note = TextEditingController(text: _original?.note ?? '');
  final _myShare = TextEditingController();
  final _theirShare = TextEditingController();

  late String _paidBy;
  late ExpenseSplit _split = _original?.split ?? ExpenseSplit.equal;
  late ExpenseCategory _category = _original?.category ?? ExpenseCategory.food;
  late DateTime _date = _dateOnly(_original?.spentOn ?? DateTime.now());
  _AutoShare _auto = _AutoShare.theirs;

  bool _saving = false;
  bool _submitted = false;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void initState() {
    super.initState();
    _coupleId = ref.read(currentCoupleIdProvider);
    _myUid = ref.read(currentUidProvider);
    _service = ref.read(expenseServiceProvider);

    final original = _original;
    final partnerUid = ref.read(coupleProvider).value?.partnerIdFor(_myUid);
    final payer = original?.paidBy;
    _paidBy = (payer != null && (payer == _myUid || payer == partnerUid))
        ? payer
        : _myUid;

    final shares = original?.shares;
    if (original != null && _split == ExpenseSplit.custom && shares != null) {
      _myShare.text = ExpenseMath.toInput(shares[_myUid] ?? 0);
      if (partnerUid != null) {
        _theirShare.text = ExpenseMath.toInput(shares[partnerUid] ?? 0);
      }
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _title.dispose();
    _note.dispose();
    _myShare.dispose();
    _theirShare.dispose();
    super.dispose();
  }

  int? get _amountMinor => ExpenseMath.parseAmount(_amount.text);

  // ------------------------------------------------------- custom shares

  /// Fills the automatic share so the two add up to the amount.
  void _fillAutoShare() {
    final amount = _amountMinor;
    if (amount == null) return;
    final source = _auto == _AutoShare.theirs ? _myShare : _theirShare;
    final target = _auto == _AutoShare.theirs ? _theirShare : _myShare;
    final entered = ExpenseMath.parseShare(source.text);
    if (entered == null || entered > amount) return;
    target.text = ExpenseMath.toInput(amount - entered);
  }

  void _setSplit(ExpenseSplit split) {
    setState(() {
      _split = split;
      if (split == ExpenseSplit.custom &&
          _myShare.text.trim().isEmpty &&
          _theirShare.text.trim().isEmpty) {
        // Start from an even split so there is something to adjust.
        final amount = _amountMinor;
        if (amount != null) {
          _myShare.text = ExpenseMath.toInput(
            _paidBy == _myUid ? amount - amount ~/ 2 : amount ~/ 2,
          );
          _auto = _AutoShare.theirs;
          _fillAutoShare();
        }
      }
    });
  }

  Map<String, int>? _draftShares(int? amount, String partnerUid) {
    if (amount == null) return null;
    final members = [_myUid, partnerUid];
    if (_split == ExpenseSplit.custom) {
      final mine = ExpenseMath.parseShare(_myShare.text);
      final theirs = ExpenseMath.parseShare(_theirShare.text);
      if (mine == null || theirs == null) return null;
      return ExpenseMath.validCustomShares(
        {_myUid: mine, partnerUid: theirs},
        amount: amount,
        memberIds: members,
      );
    }
    final draft = Expense(
      id: '',
      title: '',
      amountMinor: amount,
      paidBy: _paidBy,
      split: _split,
      spentOn: _date,
      createdBy: _myUid,
    );
    final shares = ExpenseMath.sharesFor(draft, members);
    return shares.isEmpty ? null : shares;
  }

  // ------------------------------------------------------------- actions

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: 'When was this?',
    );
    if (picked != null) setState(() => _date = _dateOnly(picked));
  }

  Future<void> _save(String partnerUid) async {
    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) return;
    final amount = _amountMinor;
    if (amount == null) return;

    Map<String, int>? shares;
    if (_split == ExpenseSplit.custom) {
      shares = _draftShares(amount, partnerUid);
      if (shares == null) return;
    }

    final original = _original;
    final expense = Expense(
      id: original?.id ?? '',
      title: _title.text.trim(),
      amountMinor: amount,
      paidBy: _paidBy,
      split: _split,
      shares: shares,
      category: _category,
      spentOn: _date,
      note: _note.text.trim(),
      // The creator never changes, even when the partner edits.
      createdBy: original?.createdBy ?? _myUid,
      createdAt: original?.createdAt,
    );

    setState(() => _saving = true);
    try {
      await _service.save(_coupleId, expense);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      context.showSnackMessage('Could not save. Check your connection.');
    }
  }

  Future<void> _delete() async {
    final original = _original;
    if (original == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this expense?'),
        content: const Text(
          'This removes it for both of you and updates the balance.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await _service.delete(_coupleId, original.id);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      context.showSnackMessage('Could not delete. Check your connection.');
    }
  }

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final couple = ref.watch(coupleProvider).value;
    final partnerName = ref.watch(partnerNameProvider);
    final currency = couple?.currency ?? Couple.defaultCurrency;
    final partnerUid = couple?.partnerIdFor(_myUid);
    final isEditing = _original != null;

    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(isEditing ? 'Edit expense' : 'New expense'),
          leading: IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: _saving ? null : () => Navigator.pop(context),
          ),
          actions: [
            // The rules let only whoever added an entry delete it.
            if (isEditing && widget.expense!.createdBy == _myUid)
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: _saving ? null : _delete,
              ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton(
                onPressed: _saving || partnerUid == null
                    ? null
                    : () => _save(partnerUid),
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
        body: partnerUid == null
            ? (couple == null
                  ? const Center(child: CircularProgressIndicator())
                  : const EmptyState(
                      icon: Icons.group_add_outlined,
                      text: 'Shared expenses start once your partner joins.',
                      padding: EdgeInsets.all(32),
                    ))
            : _form(context, partnerUid, partnerName, currency),
      ),
    );
  }

  Widget _form(
    BuildContext context,
    String partnerUid,
    String partnerName,
    String currency,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final symbol = ExpenseMath.symbolFor(currency);
    final amount = _amountMinor;
    final shares = _draftShares(amount, partnerUid);
    final payerIsMe = _paidBy == _myUid;
    final moneyInput = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    const moneyKeyboard = TextInputType.numberWithOptions(decimal: true);

    final splitHint = switch (_split) {
      ExpenseSplit.equal =>
        'Half each. If it doesn\'t divide evenly, whoever paid covers the '
            'extra ${ExpenseMath.format(1, currency)}.',
      ExpenseSplit.full =>
        payerIsMe
            ? '$partnerName owes you the whole amount. You paid for them.'
            : 'You owe $partnerName the whole amount. They paid for you.',
      ExpenseSplit.custom =>
        'Set exact amounts. Edit either one and the other fills in.',
    };

    return Form(
      key: _formKey,
      autovalidateMode: _submitted
          ? AutovalidateMode.onUserInteraction
          : AutovalidateMode.disabled,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          TextFormField(
            controller: _amount,
            autofocus: _original == null,
            keyboardType: moneyKeyboard,
            inputFormatters: moneyInput,
            textInputAction: TextInputAction.next,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            decoration: InputDecoration(
              labelText: 'Amount',
              hintText: '0.00',
              prefixText: '$symbol ',
              prefixStyle: theme.textTheme.headlineMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              helperText: amount == null
                  ? null
                  : ExpenseMath.format(amount, currency),
            ),
            validator: (v) => ExpenseMath.amountError(v ?? '', currency),
            onChanged: (_) => setState(() {
              if (_split == ExpenseSplit.custom) _fillAutoShare();
            }),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            maxLength: Expense.maxTitleLength,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'What was it for?',
              hintText: 'e.g. Dinner at Toit',
              prefixIcon: Icon(Icons.edit_note),
              counterText: '',
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Add a title' : null,
          ),
          const SizedBox(height: 20),
          const _SectionLabel('Paid by'),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              const ButtonSegment(
                value: true,
                label: Text('You'),
                icon: Icon(Icons.person_outline),
              ),
              ButtonSegment(
                value: false,
                label: Text(partnerName, overflow: TextOverflow.ellipsis),
                icon: const Icon(Icons.favorite_border),
              ),
            ],
            selected: {payerIsMe},
            onSelectionChanged: (s) =>
                setState(() => _paidBy = s.first ? _myUid : partnerUid),
          ),
          const SizedBox(height: 20),
          const _SectionLabel('Split'),
          SegmentedButton<ExpenseSplit>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: ExpenseSplit.equal,
                label: Text('Equally'),
                icon: Icon(Icons.balance),
              ),
              ButtonSegment(
                value: ExpenseSplit.full,
                label: Text('In full'),
                icon: Icon(Icons.redeem_outlined),
              ),
              ButtonSegment(
                value: ExpenseSplit.custom,
                label: Text('Custom'),
                icon: Icon(Icons.tune),
              ),
            ],
            selected: {_split},
            onSelectionChanged: (s) => _setSplit(s.first),
          ),
          const SizedBox(height: 8),
          Text(
            splitHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (_split == ExpenseSplit.custom) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _myShare,
                    keyboardType: moneyKeyboard,
                    inputFormatters: moneyInput,
                    decoration: InputDecoration(
                      labelText: 'Your share',
                      prefixText: '$symbol ',
                    ),
                    validator: (v) => ExpenseMath.parseShare(v ?? '') == null
                        ? 'Check this amount'
                        : null,
                    onChanged: (_) => setState(() {
                      _auto = _AutoShare.theirs;
                      _fillAutoShare();
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _theirShare,
                    keyboardType: moneyKeyboard,
                    inputFormatters: moneyInput,
                    decoration: InputDecoration(
                      labelText: '$partnerName\'s share',
                      prefixText: '$symbol ',
                    ),
                    validator: (v) {
                      final theirs = ExpenseMath.parseShare(v ?? '');
                      if (theirs == null) return 'Check this amount';
                      final mine = ExpenseMath.parseShare(_myShare.text);
                      final total = _amountMinor;
                      if (mine == null || total == null) return null;
                      if (mine + theirs != total) {
                        return 'Shares add up to '
                            '${ExpenseMath.format(mine + theirs, currency)}';
                      }
                      return null;
                    },
                    onChanged: (_) => setState(() {
                      _auto = _AutoShare.mine;
                      _fillAutoShare();
                    }),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          ExpenseSplitPreview(
            shares: shares,
            amountMinor: amount,
            payerUid: _paidBy,
            myUid: _myUid,
            partnerUid: partnerUid,
            partnerName: partnerName,
            currency: currency,
          ),
          const SizedBox(height: 20),
          const _SectionLabel('Category'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in ExpenseCategory.values)
                ChoiceChip(
                  label: Text('${c.emoji} ${c.label}'),
                  selected: _category == c,
                  onSelected: (_) => setState(() => _category = c),
                ),
            ],
          ),
          const SizedBox(height: 20),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(24),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Date',
                prefixIcon: Icon(Icons.event_outlined),
              ),
              child: Text(DateFormat.yMMMEd().format(_date)),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _note,
            textCapitalization: TextCapitalization.sentences,
            minLines: 2,
            maxLines: 5,
            maxLength: Expense.maxNoteLength,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              prefixIcon: Icon(Icons.notes),
              counterText: '',
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
