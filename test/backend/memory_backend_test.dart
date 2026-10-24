import 'package:couple_app/core/backend/db.dart';
import 'package:couple_app/core/backend/memory_backend.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Db db;
  setUp(() => db = Db(MemoryBackend()));

  test('set / merge / update with sentinels', () async {
    final ref = db.collection('users').doc('a');
    await ref.set({'name': 'A', 'prefs': {'x': 1, 'y': 2}});
    await ref.set({
      'prefs': {'y': 3},
      'n': FieldValue.increment(2),
    }, const SetOptions(merge: true));
    await ref.update({
      'prefs.x': FieldValue.delete(),
      'tags': FieldValue.arrayUnion(['p']),
      'at': FieldValue.serverTimestamp(),
    });
    final snap = await ref.get();
    expect(snap.exists, isTrue);
    expect(snap.data()!['prefs'], {'y': 3});
    expect(snap.data()!['n'], 2);
    expect(snap.data()!['tags'], ['p']);
    expect(snap.data()!['at'], isA<Timestamp>());
    expect(snap.get('prefs.y'), 3);
  });

  test('queries filter, order and limit; snapshots update', () async {
    final col = db.collection('couples').doc('c').collection('messages');
    for (var i = 0; i < 5; i++) {
      await col.doc('m$i').set({'n': i, 'even': i.isEven});
    }
    final q = col.where('even', isEqualTo: true).orderBy('n', descending: true).limit(2);
    expect((await q.get()).docs.map((d) => d.id), ['m4', 'm2']);
    expect((await col.count().get()).count, 5);

    final seen = <List<String>>[];
    final sub = col.orderBy('n').snapshots().listen((s) => seen.add(s.docs.map((d) => d.id).toList()));
    await pumpEventQueue();
    await col.doc('m9').set({'n': 9});
    await pumpEventQueue();
    await sub.cancel();
    expect(seen.first.length, 5);
    expect(seen.last.last, 'm9');
  });

  test('transactions retry when a read changes', () async {
    final ref = db.doc('couples/c/games/g');
    await ref.set({'turn': 0});
    var runs = 0;
    await db.runTransaction((tx) async {
      runs++;
      final s = await tx.get(ref);
      if (runs == 1) await ref.update({'turn': 5}); // someone else moves
      tx.update(ref, {'turn': (s.data()!['turn'] as int) + 1});
    });
    expect(runs, 2);
    expect((await ref.get()).data()!['turn'], 6);
  });

  test('update of missing doc and create of existing doc fail', () async {
    await expectLater(
      db.doc('users/x').update({'a': 1}),
      throwsA(isA<DbException>().having((e) => e.code, 'code', 'not-found')),
    );
    final col = db.collection('users');
    final ref = await col.add({'a': 1});
    expect(ref.id.length, 20);
  });
}
