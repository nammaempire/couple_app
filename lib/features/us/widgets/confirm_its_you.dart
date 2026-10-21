import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/app_lock/app_lock_controller.dart';
import 'package:couple_app/features/app_lock/providers/app_lock_providers.dart';
import 'package:couple_app/features/onboarding/widgets/romance_kit.dart';

/// Asks the person holding the phone to prove it's them before something
/// that can't be undone: the phone's fingerprint, face or screen lock, the
/// same prompt as the app lock.
///
/// On a phone with no lock set up, falls back to typing [fallbackWord]
/// (e.g. `END`), or lets it through when [fallbackWord] is null because the
/// next screen asks for its own confirmation. True when confirmed.
Future<bool> confirmItsYou(
  BuildContext context,
  WidgetRef ref, {
  required String reason,
  String? fallbackWord,
  String? fallbackTitle,
}) async {
  final auth = ref.read(biometricAuthProvider);
  final lock = ref.read(appLockControllerProvider.notifier);
  if (await auth.canAuthenticate()) {
    return lock.suspendWhile(auth.authenticate(reason));
  }
  if (fallbackWord == null) return true;
  if (!context.mounted) return false;
  final typed = await showDialog<bool>(
    context: context,
    builder: (_) => TypeToConfirmDialog(
      word: fallbackWord,
      title: fallbackTitle ?? 'Confirm it\'s you',
    ),
  );
  return typed == true;
}

/// "Type END to continue".
class TypeToConfirmDialog extends StatefulWidget {
  const TypeToConfirmDialog({
    super.key,
    required this.word,
    required this.title,
  });

  final String word;
  final String title;

  @override
  State<TypeToConfirmDialog> createState() => _TypeToConfirmDialogState();
}

class _TypeToConfirmDialogState extends State<TypeToConfirmDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _matches => _text.text.trim().toUpperCase() == widget.word;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This phone has no screen lock, so type ${widget.word} to go on.',
          ),
          const SizedBox(height: 14),
          TextField(
            key: const Key('type-to-confirm'),
            controller: _text,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(hintText: widget.word),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Back'),
        ),
        FilledButton(
          onPressed: _matches ? () => Navigator.pop(context, true) : null,
          style: pillButtonStyle(
            context,
            preset: GradientPreset.ocean,
            minimumSize: const Size(0, 44),
          ),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
