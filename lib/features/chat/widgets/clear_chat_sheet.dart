import 'package:flutter/material.dart';

import 'package:couple_app/features/chat/widgets/chat_chrome.dart';

/// What the user chose in [ClearChatSheet].
enum ClearChatChoice { forMe, forBoth }

/// Bottom sheet from the chat menu: clear the chat for me only, or delete
/// it for both of us.
///
/// Each choice explains itself and asks for confirmation; the sheet closes
/// with the confirmed [ClearChatChoice], or null if the user backs out.
class ClearChatSheet extends StatelessWidget {
  const ClearChatSheet({super.key, required this.partnerName});

  final String partnerName;

  Future<void> _confirmForMe(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear chat for you?'),
        content: Text(
          'Every message up to now will disappear from your account, on all '
          'your devices. $partnerName keeps the whole conversation, photos '
          'and videos included.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(72, 40)),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clear for me'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      Navigator.pop(context, ClearChatChoice.forMe);
    }
  }

  Future<void> _confirmForBoth(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteForBothDialog(partnerName: partnerName),
    );
    if (ok == true && context.mounted) {
      Navigator.pop(context, ClearChatChoice.forBoth);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      // Scrolls rather than overflowing with large text.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ChatSheetHeader(
              title: 'Clear chat',
              icon: Icons.cleaning_services_outlined,
            ),
            ChatSheetOption(
              icon: Icons.visibility_off_outlined,
              title: 'Clear for me',
              subtitle:
                  'Hides every message up to now on your account only. '
                  '$partnerName keeps their history.',
              onTap: () => _confirmForMe(context),
            ),
            ChatSheetOption(
              icon: Icons.delete_forever_outlined,
              title: 'Clear for both',
              subtitle:
                  'Permanently deletes the whole conversation, with its '
                  'photos, videos and voice messages, for both of you.',
              destructive: true,
              onTap: () => _confirmForBoth(context),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// The stronger confirmation for deleting everything: the delete button
/// stays disabled until the user ticks an explicit statement.
class _DeleteForBothDialog extends StatefulWidget {
  const _DeleteForBothDialog({required this.partnerName});

  final String partnerName;

  @override
  State<_DeleteForBothDialog> createState() => _DeleteForBothDialogState();
}

class _DeleteForBothDialogState extends State<_DeleteForBothDialog> {
  bool _understood = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      icon: Icon(Icons.delete_forever_outlined, color: scheme.error),
      title: const Text('Delete the chat for both of you?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Every message, photo, video and voice message up to now will be '
            'deleted from your phone and ${widget.partnerName}\'s. This '
            'cannot be undone.',
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: _understood,
            onChanged: (v) => setState(() => _understood = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('I understand it is gone for good'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(72, 40),
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: _understood ? () => Navigator.pop(context, true) : null,
          child: const Text('Delete for both'),
        ),
      ],
    );
  }
}
