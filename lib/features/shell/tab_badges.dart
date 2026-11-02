import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/backend/backend.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/chat/models/message.dart';
import 'package:couple_app/features/chat/providers/chat_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/couple/providers/separation_providers.dart';
import 'package:couple_app/features/together/providers/together_providers.dart';

/// Counts for the bottom navigation badges: what the partner sent or added
/// that this user hasn't looked at yet.
///
///  - Chat: the partner's messages not yet seen (the chat marks them seen).
///  - Memories: memories the partner added since this user last opened
///    Memories.
///  - Together: unopened love notes, plus calendar events, plans and songs
///    the partner added since this user last opened that section.
///  - Play: games waiting on this user (play_providers.dart).
///
/// "Last opened" times live on the user's profile at `seenAt.<section>`
/// (server time, like the items' `createdAt`), so they hold across phones
/// and reinstalls. While the partner is muted, every badge is 0.

/// Sections with a "last opened" time.
abstract final class BadgeSection {
  static const memories = 'memories';
  static const calendar = 'calendar';
  static const plans = 'plans';
  static const music = 'music';

  static const all = [memories, calendar, plans, music];
}

/// Most a badge counts; it shows "99+" beyond.
const badgeCap = 99;

String badgeLabel(int count) => count > badgeCap ? '$badgeCap+' : '$count';

/// The partner's uid, or null while unpaired.
final _partnerUidProvider = Provider.autoDispose<String?>((ref) {
  final me = ref.watch(currentUidProvider);
  return ref.watch(coupleProvider).value?.partnerIdFor(me);
});

/// This user's last-opened time per section (missing until first set).
final tabSeenAtProvider = StreamProvider.autoDispose<Map<String, DateTime>>((
  ref,
) {
  final uid = ref.watch(currentUidProvider);
  return Db.instance.doc('users/$uid').snapshots().map((snap) {
    final raw = snap.data()?['seenAt'];
    if (raw is! Map) return const <String, DateTime>{};
    return {
      for (final e in raw.entries)
        if (e.value is Timestamp) '${e.key}': (e.value as Timestamp).toDate(),
    };
  });
});

/// Records that this user just looked at [section]. Sections without a time
/// yet start counting from now, so old items never light up a badge.
Future<void> markSectionSeen(String uid, Iterable<String> sections) async {
  if (sections.isEmpty) return;
  try {
    await Db.instance.doc('users/$uid').update({
      for (final s in sections) 'seenAt.$s': FieldValue.serverTimestamp(),
    });
  } catch (_) {
    // Best effort: the badge simply stays until the next try.
  }
}

/// One kind of item the partner can add, counted since a section's time.
typedef _NewItems = ({String collection, String byField, String section});

final _newItemsProvider = StreamProvider.autoDispose.family<int, _NewItems>((
  ref,
  q,
) {
  if (ref.watch(mutePartnerProvider)) return Stream.value(0);
  final partner = ref.watch(_partnerUidProvider);
  final since = ref.watch(tabSeenAtProvider.select((v) => v.value?[q.section]));
  if (partner == null || since == null) return Stream.value(0);
  final coupleId = ref.watch(currentCoupleIdProvider);
  return Db.instance
      .collection('couples/$coupleId/${q.collection}')
      .where(q.byField, isEqualTo: partner)
      .where('createdAt', isGreaterThan: Timestamp.fromDate(since))
      .limit(badgeCap + 1)
      .snapshots()
      .map((s) => s.size);
});

int _count(Ref ref, _NewItems q) => ref.watch(_newItemsProvider(q)).value ?? 0;

/// The partner's chat messages this user hasn't seen.
final chatBadgeProvider = StreamProvider.autoDispose<int>((ref) {
  if (ref.watch(mutePartnerProvider)) return Stream.value(0);
  final partner = ref.watch(_partnerUidProvider);
  if (partner == null) return Stream.value(0);
  final clearedAt = ref.watch(chatClearedAtProvider);
  final coupleId = ref.watch(currentCoupleIdProvider);
  return Db.instance
      .collection('couples/$coupleId/messages')
      .where('senderId', isEqualTo: partner)
      .where('seen', isEqualTo: false)
      .limit(badgeCap + 1)
      .snapshots()
      .map(
        (s) => s.docs
            .where((d) => !Message.fromDoc(d).isClearedBy(clearedAt))
            .length,
      );
});

final memoriesBadgeProvider = Provider.autoDispose<int>(
  (ref) => _count(ref, (
    collection: 'memories',
    byField: 'createdBy',
    section: BadgeSection.memories,
  )),
);

final calendarBadgeProvider = Provider.autoDispose<int>(
  (ref) => _count(ref, (
    collection: 'events',
    byField: 'createdBy',
    section: BadgeSection.calendar,
  )),
);

final plansBadgeProvider = Provider.autoDispose<int>((ref) {
  var total = 0;
  for (final collection in const [
    'datePlans',
    'bucketList',
    'wishlist',
    'places',
    'expenses',
  ]) {
    total += _count(ref, (
      collection: collection,
      byField: 'createdBy',
      section: BadgeSection.plans,
    ));
  }
  return total;
});

final musicBadgeProvider = Provider.autoDispose<int>(
  (ref) => _count(ref, (
    collection: 'songs',
    byField: 'addedBy',
    section: BadgeSection.music,
  )),
);

/// Ticks every minute, so a sealed love note counts once it arrives.
final _minuteProvider = StreamProvider.autoDispose<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(minutes: 1), (_) => DateTime.now());
});

/// Love notes to this user that have arrived and aren't opened yet.
final loveNotesBadgeProvider = Provider.autoDispose<int>((ref) {
  if (ref.watch(mutePartnerProvider)) return 0;
  final now = ref.watch(_minuteProvider).value ?? DateTime.now();
  final notes = ref.watch(incomingNotesProvider).value ?? const [];
  return notes.where((n) => !n.isOpened && n.isDelivered(now)).length;
});

/// Everything new under Together.
final togetherBadgeProvider = Provider.autoDispose<int>((ref) {
  final int calendar = ref.watch(calendarBadgeProvider);
  final int notes = ref.watch(loveNotesBadgeProvider);
  final int plans = ref.watch(plansBadgeProvider);
  final int music = ref.watch(musicBadgeProvider);
  return calendar + notes + plans + music;
});
