import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/core/services/voice_playback.dart';
import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/core/widgets/voice_clip_player.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/together/data/love_note_service.dart';
import 'package:couple_app/features/together/models/love_note.dart';
import 'package:couple_app/features/together/providers/together_providers.dart';
import 'package:couple_app/features/together/widgets/note_envelope_view.dart';
import 'package:couple_app/features/together/widgets/sealed_note_view.dart';

/// Opens one love note. The recipient sees a sealed envelope until the
/// delivery time; after that, tapping it reveals the words.
class NoteReaderScreen extends ConsumerStatefulWidget {
  const NoteReaderScreen({super.key, required this.note});

  final LoveNote note;

  @override
  ConsumerState<NoteReaderScreen> createState() => _NoteReaderScreenState();
}

class _NoteReaderScreenState extends ConsumerState<NoteReaderScreen> {
  late final LoveNoteService _noteService;
  late final String _coupleId;
  late final String _myUid;

  LoveNoteContent? _content;
  bool _loading = false;
  bool _sealed = false;
  String? _error;

  bool get _isMine => widget.note.senderId == _myUid;

  @override
  void dispose() {
    if (VoicePlayback.instance.isCurrent('note-${widget.note.id}')) {
      VoicePlayback.instance.stop();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _noteService = ref.read(loveNoteServiceProvider);
    _coupleId = ref.read(currentCoupleIdProvider);
    _myUid = ref.read(currentUidProvider);
    // The sender can always reread; a delivered letter opens straight away.
    // "Open when…" envelopes wait for a tap.
    final delivered = widget.note.isDelivered(DateTime.now());
    if (_isMine ||
        (delivered &&
            (widget.note.kind == NoteKind.letter || widget.note.isOpened))) {
      _open();
    } else if (!delivered) {
      _sealed = true;
    }
  }

  Future<void> _open() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final content = await _noteService.open(
        coupleId: _coupleId,
        note: widget.note,
      );
      if (!_isMine) {
        await _noteService
            .markOpened(coupleId: _coupleId, note: widget.note)
            .catchError((_) {});
      }
      if (mounted) {
        setState(() {
          _content = content;
          _sealed = false;
        });
      }
    } on NoteSealedException {
      if (mounted) setState(() => _sealed = true);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not open this note.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _unsend() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Unsend this note?'),
        content: Text(
          'It will be removed for ${ref.read(partnerNameProvider)} too.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Unsend'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _noteService.unsend(coupleId: _coupleId, note: widget.note);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      context.showSnackMessage('Could not unsend. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final note = widget.note;
    final partnerName = ref.watch(partnerNameProvider);
    final dark = theme.brightness == Brightness.dark;

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(child: Text(_error!));
    } else if (_sealed) {
      body = SealedNoteView(note: note, partnerName: partnerName);
    } else if (_content == null) {
      body = NoteEnvelopeView(note: note, onOpen: _open);
    } else {
      final content = _content!;
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF2A2124) : const Color(0xFFFFFBF5),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: theme.colorScheme.outlineVariant),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .06),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(note.emoji, style: const TextStyle(fontSize: 32)),
                const SizedBox(height: 8),
                Text(
                  note.envelopeTitle,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_isMine ? 'To $partnerName' : 'From $partnerName'}'
                  ' · ${DateFormat.yMMMMd().format(note.deliverAt)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                if (content.body.isNotEmpty)
                  SelectableText(
                    content.body,
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.7),
                  ),
                if (content.voiceUrl != null) ...[
                  const SizedBox(height: 20),
                  VoiceClipPlayer(
                    clipId: 'note-${note.id}',
                    url: content.voiceUrl,
                    duration: note.voiceDurationMs == null
                        ? null
                        : Duration(milliseconds: note.voiceDurationMs!),
                    color: theme.colorScheme.onSurface,
                    maxWidth: 420,
                  ),
                ],
              ],
            ),
          ),
          if (_isMine) ...[
            const SizedBox(height: 16),
            Text(
              note.isOpened
                  ? '$partnerName opened this on '
                        '${DateFormat.yMMMd().add_jm().format(note.openedAt!)}.'
                  : note.isScheduled(DateTime.now())
                  ? 'Sealed until '
                        '${DateFormat.yMMMd().add_jm().format(note.deliverAt)}.'
                  : 'Not opened yet.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        actions: [
          if (_isMine)
            IconButton(
              tooltip: 'Unsend',
              icon: const Icon(Icons.delete_outline),
              onPressed: _unsend,
            ),
        ],
      ),
      body: body,
    );
  }
}
