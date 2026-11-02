import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/account/data/account_deletion.dart';
import 'package:couple_app/features/auth/data/phone_auth_gateway.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/security/data/account_reauth.dart';
import 'package:couple_app/features/security/providers/security_providers.dart';
import 'package:couple_app/features/vault/providers/vault_providers.dart';

final accountDeletionGatewayProvider = Provider<AccountDeletionGateway>(
  (ref) => FunctionsAccountDeletionGateway(),
);

/// Us → Delete my account. Explains what goes, asks to type DELETE, asks the
/// person to prove it's them again (password, Google or an SMS code), then
/// deletes everything and signs out.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  static Route<void> route() => MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => const DeleteAccountScreen(),
  );

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

enum _Step { explain, confirm, deleting }

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  static const confirmWord = 'DELETE';

  _Step _step = _Step.explain;
  final _typed = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  PhoneCodeTicket? _ticket;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _typed.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _typed.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() step) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await step();
    } on ReauthException catch (e) {
      _fail(e.message);
    } on PhoneAuthException catch (e) {
      _fail(e.message);
    } on AccountDeletionException catch (e) {
      _fail(e.message, back: true);
    } catch (_) {
      _fail(AccountDeletionFailure.other.message, back: true);
    }
  }

  void _fail(String message, {bool back = false}) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
      if (back && _step == _Step.deleting) _step = _Step.confirm;
    });
  }

  ReauthOptions get _options => ref.read(accountReauthProvider).options();

  String? get _phone => ref.read(currentUserProvider).phone;

  Future<void> _withPassword() => _run(() async {
    await ref.read(accountReauthProvider).withPassword(_password.text);
    await _delete();
  });

  Future<void> _withGoogle() => _run(() async {
    if (!await ref.read(accountReauthProvider).withGoogle()) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    await _delete();
  });

  Future<void> _sendCode() => _run(() async {
    final phone = _phone;
    if (phone == null) return;
    final ticket = await ref
        .read(phoneAuthGatewayProvider)
        .sendCode(phone, mode: PhoneAuthMode.reauth, resend: _ticket);
    if (ticket.autoVerified) {
      await _delete();
      return;
    }
    if (!mounted) return;
    setState(() {
      _ticket = ticket;
      _busy = false;
    });
  });

  Future<void> _withCode() => _run(() async {
    final ticket = _ticket;
    if (ticket == null) return;
    await ref
        .read(phoneAuthGatewayProvider)
        .confirmCode(ticket, _code.text.trim(), mode: PhoneAuthMode.reauth);
    await _delete();
  });

  /// Deletes on the server, then cleans up this phone and signs out.
  Future<void> _delete() async {
    if (!mounted) return;
    setState(() => _step = _Step.deleting);
    final uid = ref.read(currentUserProvider).uid;
    final gateway = ref.read(accountDeletionGatewayProvider);
    final signInDeleted = await gateway.deleteOnServer();
    if (!signInDeleted) await gateway.deleteSignInHere();
    try {
      // This phone's vault key for the account.
      await ref.read(deviceKeystoreProvider).clearIdentity(uid);
    } catch (_) {}
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.of(context).popUntil((r) => r.isFirst);
    await ref.read(authServiceProvider).signOut();
    messenger?.showSnackBar(
      const SnackBar(content: Text('Your account has been deleted.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step != _Step.deleting,
      child: Scaffold(
        appBar: AppBar(title: const Text('Delete my account')),
        body: SafeArea(
          child: switch (_step) {
            _Step.explain => _explain(context),
            _Step.confirm => _confirm(context),
            _Step.deleting => const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Deleting your account…'),
                ],
              ),
            ),
          },
        ),
      ),
    );
  }

  Widget _explain(BuildContext context) {
    final theme = Theme.of(context);
    final partnerName = ref.watch(partnerNameProvider);
    final paired = ref.watch(coupleProvider).value?.isComplete ?? false;
    Widget point(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.error),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Text(
          'This can\'t be undone.',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        point(
          Icons.person_off_outlined,
          'Your profile, photo, avatar and sign-in are deleted.',
        ),
        point(
          Icons.favorite_border,
          paired
              ? 'Your pairing with $partnerName ends now, and everything you '
                    'share is deleted for both of you: chat, photos, videos, '
                    'memories, plans, notes, music, games and the vault. '
                    '$partnerName will see that the pairing ended.'
              : 'Your invite stops working and anything you added is '
                    'deleted.',
        ),
        point(
          Icons.workspace_premium_outlined,
          'Premium and unused gifts end with the pairing. Google Play '
          'subscriptions are cancelled in the Play Store app.',
        ),
        point(
          Icons.receipt_long_outlined,
          'Records of purchases are kept for refunds and tax, as the law '
          'requires.',
        ),
        const SizedBox(height: 8),
        Text(
          'Want to keep anything? Save the photos and videos you love to your '
          'phone first.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          key: const Key('delete-account-type'),
          controller: _typed,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Type $confirmWord to confirm',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('delete-account-continue'),
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: _typed.text.trim().toUpperCase() == confirmWord
              ? () => setState(() => _step = _Step.confirm)
              : null,
          child: const Text('Continue'),
        ),
      ],
    );
  }

  Widget _confirm(BuildContext context) {
    final theme = Theme.of(context);
    final options = _options;
    final phone = _phone;
    final error = _error;
    final hasAny = options.any || phone != null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Text(
          'Confirm it\'s you',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'So nobody else holding your phone can delete your account.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 14),
          Text(
            error,
            key: const Key('delete-account-error'),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: 20),
        if (options.password) ...[
          TextField(
            key: const Key('delete-account-password'),
            controller: _password,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Password for ${options.passwordEmail}',
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _withPassword(),
          ),
          const SizedBox(height: 10),
          FilledButton(
            key: const Key('delete-account-with-password'),
            onPressed: _busy ? null : _withPassword,
            child: const Text('Confirm and delete'),
          ),
          const SizedBox(height: 20),
        ],
        if (options.google) ...[
          OutlinedButton.icon(
            key: const Key('delete-account-with-google'),
            onPressed: _busy ? null : _withGoogle,
            icon: const Icon(Icons.account_circle_outlined),
            label: Text('Confirm with Google (${options.googleEmail})'),
          ),
          const SizedBox(height: 20),
        ],
        if (phone != null) ...[
          if (_ticket == null)
            OutlinedButton.icon(
              key: const Key('delete-account-send-code'),
              onPressed: _busy ? null : _sendCode,
              icon: const Icon(Icons.sms_outlined),
              label: Text('Send a code to $phone'),
            )
          else ...[
            TextField(
              key: const Key('delete-account-code'),
              controller: _code,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: InputDecoration(
                labelText: 'Code sent to $phone',
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _withCode(),
            ),
            FilledButton(
              key: const Key('delete-account-with-code'),
              onPressed: _busy ? null : _withCode,
              child: const Text('Confirm and delete'),
            ),
            TextButton(
              onPressed: _busy ? null : _sendCode,
              child: const Text('Send a new code'),
            ),
          ],
        ],
        if (!hasAny)
          FilledButton(
            key: const Key('delete-account-now'),
            onPressed: _busy ? null : () => _run(_delete),
            child: const Text('Delete my account'),
          ),
        if (_busy) ...[
          const SizedBox(height: 20),
          const Center(child: CircularProgressIndicator()),
        ],
      ],
    );
  }
}
