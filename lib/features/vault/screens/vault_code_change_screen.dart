import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/vault/vault_session.dart';
import 'package:couple_app/features/vault/widgets/vault_code_pad.dart';
import 'package:couple_app/features/vault/widgets/vault_look.dart';

/// Choosing a new code (or decoy code), twice. This is also how a partner
/// resets a forgotten code from their open vault.
class VaultCodeChangeScreen extends ConsumerStatefulWidget {
  const VaultCodeChangeScreen({super.key, required this.decoy});

  /// Change the decoy code rather than the code.
  final bool decoy;

  @override
  ConsumerState<VaultCodeChangeScreen> createState() =>
      _VaultCodeChangeScreenState();
}

class _VaultCodeChangeScreenState extends ConsumerState<VaultCodeChangeScreen> {
  String? _first;
  String? _hint;
  bool _saving = false;

  Future<bool> _onCode(String code) async {
    final first = _first;
    if (first == null) {
      setState(() {
        _first = code;
        _hint = null;
      });
      return true;
    }
    if (code != first) {
      setState(() {
        _first = null;
        _hint = 'Those didn\'t match. Start again.';
      });
      return false;
    }
    setState(() => _saving = true);
    final session = ref.read(vaultSessionProvider.notifier);
    try {
      final result = widget.decoy
          ? await session.changeDecoyCode(code)
          : await session.changeCode(code);
      if (!mounted) return true;
      if (result == VaultCodeChange.rejected) {
        setState(() {
          _saving = false;
          _first = null;
          _hint = 'That code can\'t be used. Choose another.';
        });
        return false;
      }
      final partner = ref.read(partnerNameProvider);
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            widget.decoy
                ? 'Decoy code changed.'
                : 'Code changed. Tell $partner in person.',
          ),
        ),
      );
      return true;
    } catch (_) {
      if (!mounted) return false;
      setState(() {
        _saving = false;
        _first = null;
        _hint = 'Couldn\'t change it. Check your connection.';
      });
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final partner = ref.watch(partnerNameProvider);
    final confirming = _first != null;
    final title = widget.decoy ? 'New decoy code' : 'New code';
    final text = confirming
        ? 'Enter it again.'
        : widget.decoy
        ? 'Six digits that open the decoy vault. It must be different from '
              'your code.'
        : 'Six digits for both of you. $partner\'s phone will need it too.';

    return VaultBackdrop(
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
        ),
        body: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    VaultBadge(
                      icon: widget.decoy
                          ? Icons.theater_comedy_outlined
                          : Icons.key_rounded,
                      size: 56,
                    ),
                    const SizedBox(height: 14),
                    VaultTitle(confirming ? 'Once more' : title, size: 27),
                    const SizedBox(height: 8),
                    VaultText(text),
                    SizedBox(
                      height: 40,
                      child: _hint == null
                          ? null
                          : Center(
                              child: Text(
                                _hint!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: vaultBlush),
                              ),
                            ),
                    ),
                    VaultCodeEntry(
                      key: ValueKey(confirming),
                      enabled: !_saving,
                      onSubmit: _onCode,
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
