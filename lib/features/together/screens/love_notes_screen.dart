import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/core/widgets/entrance_animation.dart';
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

        final forYou = letters.length + envelopes.length;
        final unopened = [
          ...letters,
          ...envelopes,
        ].where((n) => !n.isOpened).length;
        final heroLine = [
          if (forYou > 0)
            '$forYou ${forYou == 1 ? 'note' : 'notes'} for you'
          else
            'Nothing new for you yet',
          if (waiting.isNotEmpty) '${waiting.length} on its way',
        ].join(' · ');

        var i = 0;
        Widget enter(Widget child) =>
            EntranceAnimation(index: i++, child: child);

        return Scaffold(
          body: !snapshot.hasData && !snapshot.hasError
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                  children: [
                    if (notes.isEmpty)
                      enter(
                        LoveNotesIntro(
                          partnerName: partnerName,
                          onTemplate: (t) => _compose(template: t),
                          onWrite: _compose,
                        ),
                      )
                    else
                      enter(
                        LoveNotesHero(
                          title: unopened > 0
                              ? 'Love is in the mail'
                              : 'Your love notes',
                          subtitle: heroLine,
                          onWrite: _compose,
                        ),
                      ),
                    if (waiting.isNotEmpty) ...[
                      enter(const LoveNotesSectionHeader('On its way to you')),
                      for (final n in waiting)
                        enter(
                          LoveNoteTile(
                            note: n,
                            subtitle:
                                'From $partnerName · '
                                '${_arrives(n.deliverAt, now)}',
                            sealed: true,
                            countdown: _left(n.deliverAt, now),
                            onTap: () => _open(n),
                          ),
                        ),
                    ],
                    if (envelopes.isNotEmpty) ...[
                      enter(const LoveNotesSectionHeader('Open when…')),
                      enter(
                        OpenWhenEnvelopeGrid(notes: envelopes, onOpen: _open),
                      ),
                    ],
                    if (letters.isNotEmpty) ...[
                      enter(const LoveNotesSectionHeader('For you')),
                      for (final n in letters)
                        enter(
                          LoveNoteTile(
                            note: n,
                            subtitle:
                                'From $partnerName · '
                                '${DateFormat.yMMMd().format(n.deliverAt)}',
                            unread: !n.isOpened,
                            onTap: () => _open(n),
                          ),
                        ),
                    ],
                    if (sent.isNotEmpty) ...[
                      enter(const LoveNotesSectionHeader('Sent by you')),
                      for (final n in sent)
                        enter(
                          LoveNoteTile(
                            note: n,
                            subtitle: _sentStatus(n, now, partnerName),
                            muted: true,
                            onTap: () => _open(n),
                          ),
                        ),
                    ],
                    if (notes.isNotEmpty) ...[
                      enter(
                        const LoveNotesSectionHeader(
                          'Write an “Open when…” note',
                        ),
                      ),
                      enter(
                        OpenWhenTemplateRow(
                          onTemplate: (t) => _compose(template: t),
                        ),
                      ),
                    ],
                  ],
                ),
        );
      },
    );
  }

  /// "2d 14h" or "5h 20m" until a sealed note arrives.
  static String _left(DateTime at, DateTime now) {
    final left = at.difference(now);
    if (left.inMinutes < 1) return 'soon';
    if (left.inDays > 0) return '${left.inDays}d ${left.inHours % 24}h';
    if (left.inHours > 0) return '${left.inHours}h ${left.inMinutes % 60}m';
    return '${left.inMinutes}m';
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
