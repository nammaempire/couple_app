import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/onboarding/widgets/busy_button_label.dart';
import 'package:couple_app/features/onboarding/widgets/romance_kit.dart';
import 'package:couple_app/features/security/data/account_reauth.dart';
import 'package:couple_app/features/security/providers/security_providers.dart';

/// Adds an email and password to the account, so a new phone can be
/// confirmed with them. True once added.
Future<bool> showAddRecoveryEmailSheet(BuildContext context) async {
  final added = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const AddRecoveryEmailSheet(),
  );
  return added == true;
}

class AddRecoveryEmailSheet extends ConsumerStatefulWidget {
  const AddRecoveryEmailSheet({super.key});

  @override
  ConsumerState<AddRecoveryEmailSheet> createState() =>
      _AddRecoveryEmailSheetState();
}

class _AddRecoveryEmailSheetState extends ConsumerState<AddRecoveryEmailSheet> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _emailError;
  String? _passwordError;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  static bool _looksLikeEmail(String s) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s);

  Future<void> _add() async {
    final email = _email.text.trim();
    final password = _password.text;
    setState(() {
      _emailError = _looksLikeEmail(email) ? null : 'Enter your email.';
      _passwordError = password.length >= 6
          ? null
          : 'Use at least 6 characters.';
      _error = null;
    });
    if (_emailError != null || _passwordError != null) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(accountReauthProvider)
          .addRecoveryEmail(email: email, password: password);
      ref.invalidate(reauthOptionsProvider);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Recovery email added. We sent $email a note to '
            'verify it.',
          ),
        ),
      );
    } on ReauthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) context.showSnackMessage('Couldn\'t add it. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHeader(
              icon: Icons.alternate_email_rounded,
              preset: GradientPreset.ocean,
              title: 'Add a recovery email',
              subtitle:
                  'If you ever sign in on a new phone, this email and '
                  'password confirm it\'s you in a minute.',
            ),
            TextField(
              key: const Key('recovery-email-field'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Email',
                prefixIcon: const Icon(Icons.mail_outline),
                errorText: _emailError,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('recovery-password-field'),
              controller: _password,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              onSubmitted: (_) => _busy ? null : _add(),
              decoration: InputDecoration(
                labelText: 'Choose a password',
                prefixIcon: const Icon(Icons.lock_outline),
                errorText: _passwordError,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton(
              key: const Key('recovery-email-add'),
              onPressed: _busy ? null : _add,
              style: pillButtonStyle(context, preset: GradientPreset.ocean),
              child: BusyButtonLabel(busy: _busy, label: 'Add email'),
            ),
          ],
        ),
      ),
    );
  }
}
