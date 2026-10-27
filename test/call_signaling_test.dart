import 'package:couple_app/core/backend/db.dart';
import 'package:couple_app/core/backend/memory_backend.dart';
import 'package:couple_app/features/calls/data/call_signaling.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('signals reach only the partner, in order, scoped to the call', () async {
    final db = Db(MemoryBackend());
    final signaling = CallSignaling(db);
    final seen = <List<String>>[];
    final sub = signaling
        .watch(coupleId: 'c1', callId: 'call1', to: 'bob')
        .listen((list) => seen.add([for (final s in list) s.kind]));
    await pumpEventQueue();

    await signaling.send(coupleId: 'c1', callId: 'call1', from: 'ann', to: 'bob', kind: 'offer', payload: {'sdp': 'o'});
    await signaling.send(coupleId: 'c1', callId: 'call1', from: 'bob', to: 'ann', kind: 'answer', payload: {'sdp': 'a'});
    await signaling.send(coupleId: 'c1', callId: 'other', from: 'ann', to: 'bob', kind: 'offer', payload: {});
    await signaling.send(coupleId: 'c1', callId: 'call1', from: 'ann', to: 'bob', kind: 'candidates', payload: {'candidates': []});
    await pumpEventQueue();
    await sub.cancel();

    expect(seen.last, ['offer', 'candidates']);

    await signaling.clear('c1');
    final left = await db.collection('couples/c1/callSignals').get();
    expect(left.size, 0);
  });
}
