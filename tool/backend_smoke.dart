// Smoke test of the app's data layer against a running Us server started with
// `npx tsx test/dev-open-server.ts` (server/). Usage:
//   dart run tool/backend_smoke.dart http://127.0.0.1:18080
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:couple_app/core/backend/backend.dart';
import 'package:http/http.dart' as http;

Future<void> main(List<String> args) async {
  final base = args.isEmpty ? 'http://127.0.0.1:18080' : args.first;
  final api = ApiClient(baseUrl: base, token: ({bool forceRefresh = false}) async => 'test:alice');
  final realtime = Realtime(api);
  final db = Db(RemoteBackend(api, realtime: realtime));
  final files = Files(api);
  final fns = Functions(api);
  void check(bool ok, String what) {
    stdout.writeln('${ok ? 'PASS' : 'FAIL'}  $what');
    if (!ok) exitCode = 1;
  }

  final couple = db.collection('couples').doc('smoke');
  await couple.set({'memberIds': ['alice', 'bob'], 'since': DateTime.utc(2024, 2, 14)});
  final s = await couple.get();
  check(s.exists && (s.data()!['since'] as Timestamp).toDate().toUtc().year == 2024, 'set + get with timestamp');

  await couple.update({'separation.status': 'agreed', 'separation.at': FieldValue.serverTimestamp()});
  final s2 = await couple.get();
  check((s2.data()!['separation'] as Map)['status'] == 'agreed', 'dotted update');

  final msgs = couple.collection('messages');
  final live = <int>[];
  final done = Completer<void>();
  final firstSnap = Completer<void>();
  final sub = msgs.orderBy('sentAt', descending: true).limit(10).snapshots().listen((q) {
    live.add(q.size);
    if (!firstSnap.isCompleted) firstSnap.complete();
    if (q.size == 3 && !done.isCompleted) done.complete();
  });
  await firstSnap.future.timeout(const Duration(seconds: 5));
  for (var i = 0; i < 3; i++) {
    await msgs.add({'senderId': 'alice', 'text': 'hi $i', 'sentAt': FieldValue.serverTimestamp()});
  }
  await done.future.timeout(const Duration(seconds: 5));
  await sub.cancel();
  check(live.first == 0 && live.last == 3, 'live query snapshots ($live)');

  final docStream = couple.snapshots();
  final first = await docStream.first;
  check(first.data()!['memberIds'] is List, 'live doc snapshot');

  final n = await msgs.where('senderId', isEqualTo: 'alice').count().get();
  check(n.count == 3, 'count()');

  final batch = db.batch();
  final q = await msgs.get();
  for (final d in q.docs) {
    batch.delete(d.reference);
  }
  await batch.commit();
  check((await msgs.get()).size == 0, 'batch delete');

  final game = couple.collection('games').doc('g1');
  await game.set({'turn': 0});
  await Future.wait([
    for (var i = 0; i < 5; i++)
      db.runTransaction((tx) async {
        final g = await tx.get(game);
        tx.update(game, {'turn': (g.data()!['turn'] as int) + 1});
      }),
  ]);
  check((await game.get()).data()!['turn'] == 5, 'concurrent transactions');

  try {
    await db.doc('couples/smoke/games/none').update({'x': 1});
    check(false, 'update missing → not-found');
  } on DbException catch (e) {
    check(e.code == 'not-found', 'update missing → not-found');
  }

  final ref = files.ref('couples/smoke/photos/p1.jpg');
  final progress = <int>[];
  final task = ref.putData(Uint8List.fromList(List.generate(300000, (i) => i % 256)), const FileMetadata(contentType: 'image/jpeg'));
  task.snapshotEvents.listen((e) => progress.add(e.bytesTransferred));
  await task;
  final url = await ref.getDownloadURL();
  check(url.contains('/f/couples/smoke/photos/p1.jpg?t='), 'upload + download URL');
  check(progress.isNotEmpty && progress.last == 300000, 'upload progress');
  check(files.refFromURL(url).fullPath == 'couples/smoke/photos/p1.jpg', 'refFromURL');
  final redirect = await http.Client().send(http.Request('GET', Uri.parse(url))..followRedirects = false);
  check(redirect.statusCode == 302, 'download link redirects (${redirect.statusCode})');
  await ref.delete();
  try {
    await ref.getDownloadURL();
    check(false, 'deleted file is gone');
  } on DbException catch (e) {
    check(e.code == 'not-found', 'deleted file is gone');
  }

  final r = await fns.call('echo', {'x': 1});
  check(r is Map && r['uid'] == 'alice', 'server function call');
  try {
    await fns.call('nope');
  } on FunctionsException catch (e) {
    check(e.code == 'not-found', 'unknown function → not-found');
  }

  await realtime.close();
  api.close();
  exit(exitCode);
}
