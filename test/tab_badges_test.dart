import 'dart:async';

import 'package:couple_app/core/backend/backend.dart';
import 'package:couple_app/core/backend/memory_backend.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/chat/providers/chat_providers.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/couple/providers/separation_providers.dart';
import 'package:couple_app/features/shell/tab_badges.dart';
import 'package:couple_app/features/together/models/love_note.dart';
import 'package:couple_app/features/together/providers/together_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MemoryBackend backend;
  late StreamController<List<LoveNote>> notes;
  late ProviderContainer c;

  setUp(() {
    backend = MemoryBackend();
    Db.instance = Db(backend);
    notes = StreamController<List<LoveNote>>.broadcast();
    c = ProviderContainer(
      overrides: [
        currentUidProvider.overrideWithValue('ann'),
        currentCoupleIdProvider.overrideWithValue('c1'),
        coupleProvider.overrideWith(
          (ref) => Stream.value(
            const Couple(id: 'c1', inviteCode: 'X', memberIds: ['ann', 'bob']),
          ),
        ),
        mutePartnerProvider.overrideWithValue(false),
        chatClearedAtProvider.overrideWithValue(null),
        incomingNotesProvider.overrideWith((ref) => notes.stream),
      ],
    );
  });

  tearDown(() async {
    c.dispose();
    await notes.close();
  });

  /// Keeps [p] alive and returns its latest value after things settle.
  Future<T> read<T>(ProviderListenable<T> p) async {
    final sub = c.listen(p, (_, _) {}, fireImmediately: true);
    await pumpEventQueue(times: 30);
    final v = sub.read();
    return v;
  }

  Future<void> add(String path, Map<String, Object?> data) => Db.instance
      .doc(path)
      .set({...data, 'createdAt': FieldValue.serverTimestamp()});

  test('chat: the partner\'s unseen messages', () async {
    await add('couples/c1/messages/m1', {'senderId': 'bob', 'seen': false});
    await add('couples/c1/messages/m2', {'senderId': 'bob', 'seen': false});
    await add('couples/c1/messages/m3', {'senderId': 'bob', 'seen': true});
    await add('couples/c1/messages/m4', {'senderId': 'ann', 'seen': false});
    expect((await read(chatBadgeProvider)).value, 2);

    await Db.instance.doc('couples/c1/messages/m1').update({'seen': true});
    expect((await read(chatBadgeProvider)).value, 1);
  });

  test(
    'memories: only what the partner added since Memories was opened',
    () async {
      backend.clock = DateTime.utc(2026, 10, 1);
      await add('couples/c1/memories/old', {'createdBy': 'bob'});
      await Db.instance.doc('users/ann').set({
        'seenAt': {'memories': Timestamp.fromDate(DateTime.utc(2026, 10, 2))},
      });
      backend.clock = DateTime.utc(2026, 10, 3);
      await add('couples/c1/memories/new1', {'createdBy': 'bob'});
      await add('couples/c1/memories/mine', {'createdBy': 'ann'});
      expect(await read(memoriesBadgeProvider), 1);

      // Opening Memories resets the clock.
      backend.clock = DateTime.utc(2026, 10, 4);
      await markSectionSeen('ann', const [BadgeSection.memories]);
      expect(await read(memoriesBadgeProvider), 0);
    },
  );

  test('no clock yet: nothing counts (old items never light up)', () async {
    await add('couples/c1/events/e1', {'createdBy': 'bob'});
    expect(await read(calendarBadgeProvider), 0);
  });

  test('together adds up calendar, plans, music and unopened notes', () async {
    backend.clock = DateTime.utc(2026, 10, 1);
    await Db.instance.doc('users/ann').set({
      'seenAt': {
        for (final s in BadgeSection.all) s: FieldValue.serverTimestamp(),
      },
    });
    backend.clock = DateTime.utc(2026, 10, 2);
    await add('couples/c1/events/e1', {'createdBy': 'bob'});
    await add('couples/c1/bucketList/b1', {'createdBy': 'bob'});
    await add('couples/c1/expenses/x1', {'createdBy': 'bob'});
    await add('couples/c1/songs/s1', {'addedBy': 'bob'});

    final sub = c.listen(togetherBadgeProvider, (_, _) {});
    await pumpEventQueue(times: 30);
    final now = DateTime.now();
    notes.add([
      LoveNote(
        id: 'n1',
        senderId: 'bob',
        recipientId: 'ann',
        kind: NoteKind.letter,
        title: 'hi',
        deliverAt: now.subtract(const Duration(minutes: 1)),
      ),
      // Sealed until tomorrow: not counted yet.
      LoveNote(
        id: 'n2',
        senderId: 'bob',
        recipientId: 'ann',
        kind: NoteKind.letter,
        title: 'later',
        deliverAt: now.add(const Duration(days: 1)),
      ),
      // Already opened.
      LoveNote(
        id: 'n3',
        senderId: 'bob',
        recipientId: 'ann',
        kind: NoteKind.letter,
        title: 'read',
        deliverAt: now.subtract(const Duration(days: 1)),
        openedAt: now,
      ),
    ]);
    await pumpEventQueue(times: 30);

    expect(c.read(calendarBadgeProvider), 1);
    expect(c.read(plansBadgeProvider), 2);
    expect(c.read(musicBadgeProvider), 1);
    expect(c.read(loveNotesBadgeProvider), 1);
    expect(sub.read(), 5);
  });

  test('a muted partner shows no badges', () async {
    final muted = ProviderContainer(
      overrides: [
        currentUidProvider.overrideWithValue('ann'),
        currentCoupleIdProvider.overrideWithValue('c1'),
        coupleProvider.overrideWith(
          (ref) => Stream.value(
            const Couple(id: 'c1', inviteCode: 'X', memberIds: ['ann', 'bob']),
          ),
        ),
        mutePartnerProvider.overrideWithValue(true),
        chatClearedAtProvider.overrideWithValue(null),
        incomingNotesProvider.overrideWith((ref) => notes.stream),
      ],
    );
    addTearDown(muted.dispose);
    await add('couples/c1/messages/m1', {'senderId': 'bob', 'seen': false});
    final sub = muted.listen(chatBadgeProvider, (_, _) {});
    await pumpEventQueue(times: 30);
    expect(sub.read().value, 0);
  });

  test('badge labels cap at 99+', () {
    expect(badgeLabel(7), '7');
    expect(badgeLabel(100), '99+');
  });
}
