import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/core/services/voice_playback.dart';
import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/floating_hearts.dart';
import 'package:couple_app/core/widgets/glass.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/home/models/love_tap.dart';
import 'package:couple_app/features/home/providers/home_providers.dart';
import 'package:couple_app/features/together/data/love_note_service.dart';
import 'package:couple_app/features/together/models/love_note.dart';
import 'package:couple_app/features/together/providers/together_providers.dart';
import 'package:couple_app/features/together/screens/note_composer_screen.dart';
import 'package:couple_app/features/together/widgets/love_letter_view.dart';
import 'package:couple_app/features/together/widgets/note_envelope_view.dart';
import 'package:couple_app/features/together/widgets/note_theme.dart';
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

  /// Opened from the envelope here, so the reveal plays.
  bool _tappedOpen = false;
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

  Future<void> _sendKiss() async {
    await HapticFeedback.mediumImpact();
    try {
      await ref
          .read(nudgeServiceProvider)
          .send(coupleId: _coupleId, senderId: _myUid, kind: LoveTap.kiss);
      if (!mounted) return;
      context.showSnackMessage(
        'Kiss sent to ${ref.read(partnerNameProvider)} ${LoveTap.kiss.emoji}',
      );
    } catch (_) {
      if (!mounted) return;
      context.showSnackMessage('Could not send. Check your connection.');
    }
  }

  void _writeBack() {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const NoteComposerScreen(),
      ),
    );
  }

  String? _status(String partnerName) {
    if (!_isMine) return null;
    final note = widget.note;
    return note.isOpened
        ? '$partnerName opened this on '
              '${DateFormat.yMMMd().add_jm().format(note.openedAt!)}.'
        : note.isScheduled(DateTime.now())
        ? 'Sealed until '
              '${DateFormat.yMMMd().add_jm().format(note.deliverAt)}.'
        : 'Not opened yet.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final note = widget.note;
    final partnerName = ref.watch(partnerNameProvider);
    final myName = ref.watch(profileProvider(_myUid)).value?.displayName ?? '';
    final b = theme.brightness;
    final look = NoteTheme.of(note);
    final fg = look.preset.foreground(b);
    final darkBg = look.preset.isDarkIn(b);
    final envelope = _content == null && !_sealed && _error == null;

    Widget body;
    if (_loading && !envelope) {
      body = Center(child: CircularProgressIndicator(color: fg));
    } else if (_error != null) {
      body = Center(
        child: GlassPanel(
          dark: darkBg,
          child: Text(_error!, style: TextStyle(color: fg)),
        ),
      );
    } else if (_sealed) {
      body = SealedNoteView(note: note, partnerName: partnerName);
    } else if (_content == null) {
      body = SafeArea(
        child: _loading && !_tappedOpen
            ? Center(child: CircularProgressIndicator(color: fg))
            : NoteEnvelopeView(
                note: note,
                from: _isMine ? null : partnerName,
                opening: _loading,
                onOpen: () {
                  _tappedOpen = true;
                  _open();
                },
              ),
      );
    } else {
      body = LoveLetterView(
        note: note,
        content: _content!,
        isMine: _isMine,
        partnerName: partnerName,
        myName: _isMine ? (myName.isEmpty ? 'You' : myName) : myName,
        reveal: !_isMine && (_tappedOpen || !note.isOpened),
        status: _status(partnerName),
        actions: [
          if (!_isMine) ...[
            GlassChip(
              dark: darkBg,
              leading: const Text('❤️', style: TextStyle(fontSize: 16)),
              label: 'Send a kiss back',
              onTap: _sendKiss,
            ),
            GlassChip(
              dark: darkBg,
              leading: const Text('✍️', style: TextStyle(fontSize: 16)),
              label: 'Write back',
              onTap: _writeBack,
            ),
          ],
        ],
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: look.preset.colors(b).first,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        foregroundColor: fg,
        systemOverlayStyle: darkBg
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        actions: [
          if (_isMine)
            IconButton(
              tooltip: 'Unsend',
              icon: const Icon(Icons.delete_outline),
              onPressed: _unsend,
            ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedGradientBackground(preset: look.preset),
          ),
          Positioned.fill(
            child: FloatingHearts(
              style: look.particles,
              color: look.particleColor(b),
              count: look.particles == ParticleStyle.stars ? 34 : 16,
              opacity: look.particles == ParticleStyle.stars ? .8 : .5,
            ),
          ),
          Positioned.fill(child: body),
        ],
      ),
    );
  }
}
