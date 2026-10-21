import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/couple/widgets/separation_banner.dart';
import 'package:couple_app/features/home/models/daily_question.dart';
import 'package:couple_app/features/home/models/important_date.dart';
import 'package:couple_app/features/home/models/love_tap.dart';
import 'package:couple_app/features/home/providers/home_providers.dart';
import 'package:couple_app/features/home/widgets/coming_up_card.dart';
import 'package:couple_app/features/home/widgets/couple_header.dart';
import 'package:couple_app/features/home/widgets/daily_question_card.dart';
import 'package:couple_app/features/home/widgets/love_taps_card.dart';
import 'package:couple_app/features/home/widgets/mood_card.dart';
import 'package:couple_app/features/home/widgets/quick_actions.dart';
import 'package:couple_app/features/home/widgets/recent_memories_strip.dart';
import 'package:couple_app/features/home/widgets/together_counter.dart';
import 'package:couple_app/features/memories/models/memory.dart';
import 'package:couple_app/features/memories/providers/memory_providers.dart';
import 'package:couple_app/features/memories/screens/memory_detail_screen.dart';
import 'package:couple_app/features/memories/screens/memory_editor_screen.dart';
import 'package:couple_app/features/plans/providers/date_plan_providers.dart';
import 'package:couple_app/features/premium/widgets/unopened_gift_card.dart';
import 'package:couple_app/features/together/providers/together_providers.dart';
import 'package:couple_app/features/together/screens/event_editor_screen.dart';
import 'package:couple_app/features/together/screens/note_composer_screen.dart';

/// What a StreamBuilder's `snapshot.data` would be: like `.value`, but null
/// after an error instead of keeping the last good value.
T? _dataOf<T>(AsyncValue<T> value) => value.hasError ? null : value.value;

/// The emotional centre of the app: who you are together, what is coming
/// up, how you are both doing, and one-tap ways to reach each other.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({
    super.key,
    this.onOpenChat,
    this.onOpenMemories,
    this.onOpenCalendar,
  });

  /// Switch to the Chat tab.
  final VoidCallback? onOpenChat;

  /// Switch to the Memories tab.
  final VoidCallback? onOpenMemories;

  /// Switch to the Together tab's calendar.
  final VoidCallback? onOpenCalendar;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  // The mood, daily-question and memory streams live in providers, so they
  // are created once rather than resubscribed whenever the couple document
  // updates (which it does on every message).

  /// Only called from callbacks, which exist once [build] has a couple.
  Couple get couple => ref.read(coupleProvider).value!;
  AppUser get _me => ref.read(currentUserProvider);
  String? get _partnerUid => couple.partnerIdFor(_me.uid);

  Future<void> _pickStartDate() async {
    final couple = this.couple;
    final couples = ref.read(coupleServiceProvider);
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: couple.startDate ?? now,
      firstDate: DateTime(1970),
      lastDate: now,
      helpText: 'When did you two start?',
    );
    if (picked == null) return;
    await couples.setStartDate(coupleId: couple.id, date: picked);
  }

  Future<void> _sendLove(LoveTap tap) {
    return ref
        .read(nudgeServiceProvider)
        .send(coupleId: couple.id, senderId: _me.uid, kind: tap);
  }

  void _push(Widget screen, {bool dialog = true}) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(fullscreenDialog: dialog, builder: (_) => screen));
  }

  void _addMemory() => _push(const MemoryEditorScreen());

  void _addEvent() => _push(const EventEditorScreen());

  void _writeNote() {
    if (_partnerUid == null) return;
    _push(const NoteComposerScreen());
  }

  void _openMemory(Memory memory) => _push(
    MemoryDetailScreen(memoryId: memory.id, initial: memory),
    dialog: false,
  );

  @override
  Widget build(BuildContext context) {
    // MainShell only shows this tab once the couple has loaded.
    final couple = ref.watch(coupleProvider).value;
    if (couple == null) return const SizedBox.shrink();
    final me = ref.watch(currentUserProvider);
    final partner = ref.watch(partnerProvider).value;
    final partnerName = ref.watch(partnerNameProvider);
    final events = ref.watch(eventsProvider).value ?? const [];
    final incomingNotes = ref.watch(incomingNotesProvider).value ?? const [];
    final memories = _dataOf(ref.watch(memoriesProvider));
    final moods = _dataOf(ref.watch(moodsProvider));
    final history = _dataOf(ref.watch(questionHistoryProvider));
    final today = _dataOf(ref.watch(todayQuestionProvider));

    final partnerUid = couple.partnerIdFor(me.uid);
    final paired = couple.isComplete;
    final dates = ImportantDate.upcoming(
      couple: couple,
      me: me,
      partner: partner,
      partnerName: partnerName,
      events: [...events, ...ref.watch(plannedDateEventsProvider)],
      incomingNotes: incomingNotes,
    );
    final streak = QuestionBank.streak(
      (history ?? const []).map((e) => e.dateKey),
      DateTime.now(),
    );
    final todayEntry =
        today ??
        DailyQuestionEntry(
          dateKey: QuestionBank.dateKeyFor(DateTime.now()),
          prompt: QuestionBank.promptFor(DateTime.now(), couple.id),
        );

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          children: [
            CoupleHeader(
              greeting: _greeting(me),
              subtitle: couple.coupleName ?? 'You and $partnerName',
              myName: me.displayName,
              partnerName: partnerName,
              me: me,
              partner: partner,
              couplePhotoUrl: couple.photoUrl,
            ),
            const SizedBox(height: 16),
            if (couple.isSeparating) ...[
              SeparationBanner(onOpenChat: widget.onOpenChat),
              const SizedBox(height: 16),
            ],
            const UnopenedGiftCard(),

            QuickActions(
              actions: [
                QuickAction(
                  icon: Icons.chat_bubble_outline,
                  label: 'Message',
                  onPressed: widget.onOpenChat,
                ),
                QuickAction(
                  icon: Icons.add_photo_alternate_outlined,
                  label: 'Memory',
                  onPressed: _addMemory,
                ),
                QuickAction(
                  icon: Icons.event_outlined,
                  label: 'Event',
                  onPressed: _addEvent,
                ),
                QuickAction(
                  icon: Icons.edit_note,
                  label: 'Note',
                  onPressed: paired ? _writeNote : null,
                ),
              ],
            ),
            const SizedBox(height: 16),

            TogetherCounter(couple: couple, onSetStartDate: _pickStartDate),
            const SizedBox(height: 16),

            LoveTapsCard(
              partnerName: partnerName,
              enabled: paired,
              onSend: _sendLove,
            ),
            const SizedBox(height: 16),

            ComingUpCard(
              dates: dates,
              onAddDates: _addEvent,
              onSeeCalendar: widget.onOpenCalendar,
            ),
            const SizedBox(height: 16),

            RecentMemoriesStrip(
              memories: (memories ?? const <Memory>[]).take(8).toList(),
              onOpen: _openMemory,
              onSeeAll: widget.onOpenMemories ?? () {},
              onAdd: _addMemory,
            ),
            const SizedBox(height: 16),

            MoodCard(
              myUid: me.uid,
              partnerUid: partnerUid,
              partnerName: partnerName,
              moods: moods ?? const {},
              onPick: (mood, note) => ref
                  .read(moodServiceProvider)
                  .setMood(
                    coupleId: couple.id,
                    uid: me.uid,
                    mood: mood,
                    note: note,
                  ),
            ),
            const SizedBox(height: 16),

            DailyQuestionCard(
              entry: todayEntry,
              myUid: me.uid,
              partnerUid: partnerUid,
              partnerName: partnerName,
              streak: streak,
              onAnswer: (text) => ref
                  .read(dailyQuestionServiceProvider)
                  .answer(coupleId: couple.id, uid: me.uid, text: text),
            ),
          ],
        ),
      ),
    );
  }

  String _greeting(AppUser me) {
    final hour = DateTime.now().hour;
    final name = me.nickname ?? me.displayName;
    final base = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : hour < 21
        ? 'Good evening'
        : 'Still up';
    return hour < 21 ? '$base, $name' : '$base, $name?';
  }
}
