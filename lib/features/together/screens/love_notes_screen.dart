import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/together/models/love_note.dart';
import 'package:couple_app/features/together/providers/together_providers.dart';
import 'package:couple_app/features/together/screens/note_composer_screen.dart';
import 'package:couple_app/features/together/screens/note_reader_screen.dart';
import 'package:couple_app/features/together/widgets/love_note_tile.dart';
import 'package:couple_app/features/together/widgets/love_notes_intro.dart';
import 'package:couple_app/features/together/widgets/love_notes_section_header.dart';
import 'package:couple_app/features/together/widgets/open_when_envelope_grid.dart';
import 'package:couple_app/features/together/widgets/open_when_template_row.dart';

/// Love notes: letters that arrive now or on a date, and "Open when…"
/// envelopes to keep for the right moment.
class LoveNotesScreen extends ConsumerStatefulWidget {
  const LoveNotesScreen({super.key});

  @override
  ConsumerState<LoveNotesScreen> createState() => _LoveNotesScreenState();
}

class _LoveNotesScreenState extends ConsumerState<LoveNotesScreen> {
  late final String _myUid;

  @override
  void initState() {
    super.initState();
    _myUid = ref.read(currentUidProvider);
  }

  late final Stream<List<LoveNote>> _notes = ref
      .read(loveNoteServiceProvider)
      .watchNotes(ref.read(currentCoupleIdProvider));

  String? get _partnerUid =>
      ref.read(coupleProvider).value?.partnerIdFor(_myUid);

  void _compose({OpenWhen? template}) {
    final partnerUid = _partnerUid;
    if (partnerUid == null) {
      context.showSnackMessage('Pair with your partner first.');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => NoteComposerScreen(template: template),
      ),
    );
  }

  void _open(LoveNote note) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => NoteReaderScreen(note: note)));
  }

  @override
  Widget build(BuildContext context) {
    final partnerName = ref.watch(partnerNameProvider);
    return StreamBuilder<List<LoveNote>>(
      stream: _notes,
      builder: (context, snapshot) {
        final now = DateTime.now();
        final notes = snapshot.data ?? const <LoveNote>[];
        final received = notes.where((n) => n.recipientId == _myUid).toList();
        final sent = notes.where((n) => n.senderId == _myUid).toList();

        final waiting = received.where((n) => n.isScheduled(now)).toList()
          ..sort((a, b) => a.deliverAt.compareTo(b.deliverAt));
        final envelopes = received
            .where((n) => n.kind == NoteKind.openWhen && n.isDelivered(now))
            .toList();
        final letters = received
            .where((n) => n.kind == NoteKind.letter && n.isDelivered(now))
            .toList();

        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'write-note',
            onPressed: _compose,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Write a note'),
          ),
          body: !snapshot.hasData && !snapshot.hasError
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                  children: [
                    if (notes.isEmpty)
                      LoveNotesIntro(
                        partnerName: partnerName,
                        onTemplate: (t) => _compose(template: t),
                      ),
                    if (waiting.isNotEmpty) ...[
                      const LoveNotesSectionHeader('On its way to you'),
                      for (final n in waiting)
                        LoveNoteTile(
                          note: n,
                          subtitle:
                              'From $partnerName · '
                              '${_arrives(n.deliverAt, now)}',
                          sealed: true,
                          onTap: () => _open(n),
                        ),
                    ],
                    if (envelopes.isNotEmpty) ...[
                      const LoveNotesSectionHeader('Open when…'),
                      OpenWhenEnvelopeGrid(notes: envelopes, onOpen: _open),
                    ],
                    if (letters.isNotEmpty) ...[
                      const LoveNotesSectionHeader('For you'),
                      for (final n in letters)
                        LoveNoteTile(
                          note: n,
                          subtitle:
                              'From $partnerName · '
                              '${DateFormat.yMMMd().format(n.deliverAt)}',
                          unread: !n.isOpened,
                          onTap: () => _open(n),
                        ),
                    ],
                    if (sent.isNotEmpty) ...[
                      const LoveNotesSectionHeader('Sent by you'),
                      for (final n in sent)
                        LoveNoteTile(
                          note: n,
                          subtitle: _sentStatus(n, now, partnerName),
                          onTap: () => _open(n),
                        ),
                    ],
                    if (notes.isNotEmpty) ...[
                      const LoveNotesSectionHeader(
                        'Write an “Open when…” note',
                      ),
                      OpenWhenTemplateRow(
                        onTemplate: (t) => _compose(template: t),
                      ),
                    ],
                  ],
                ),
        );
      },
    );
  }

  static String _arrives(DateTime at, DateTime now) {
    final days = DateTime(
      at.year,
      at.month,
      at.day,
    ).difference(DateTime(now.year, now.month, now.day)).inDays;
    if (days <= 0) return 'arrives at ${DateFormat.jm().format(at)}';
    if (days == 1) return 'arrives tomorrow';
    if (days < 7) return 'arrives in $days days';
    return 'arrives ${DateFormat.MMMd().format(at)}';
  }

  String _sentStatus(LoveNote n, DateTime now, String partnerName) {
    if (n.isScheduled(now)) {
      return 'To $partnerName · ${_arrives(n.deliverAt, now)}';
    }
    if (n.isOpened) {
      return 'Opened ${DateFormat.MMMd().format(n.openedAt!)}';
    }
    return n.kind == NoteKind.openWhen
        ? 'Waiting for the right moment'
        : 'Delivered · not opened yet';
  }
}
