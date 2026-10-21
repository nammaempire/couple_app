const assert = require('node:assert/strict');
const h = require('./helpers.js');
const { processSeparations, finalizeSeparation, leaveNow } = require('../lib/index.js');

// v2 functions expose their handler as `.run`; we pass fake auth contexts.
const call = (fn, uid, data) => fn.run({ data, auth: uid ? { uid, token: { uid } } : undefined, rawRequest: {} });
const tick = () => processSeparations.run({ scheduleTime: new Date().toISOString(), jobName: 'test' });

async function rejectsWith(promise, code, re) {
  await assert.rejects(promise, (e) => {
    assert.equal(e.code, code, `expected ${code}, got ${e.code}: ${e.message}`);
    if (re) assert.match(e.message, re);
    return true;
  });
}

const sep = (o) => ({
  separation: {
    requestedBy: 'alice', requestedAt: h.ts(-20 * h.DAY), status: 'requested',
    agreedAt: null, declinedAt: null, effectiveAt: h.ts(-h.DAY), ...o,
  },
});
const exists = async (cid) => (await h.db().doc(`couples/${cid}`).get()).exists;
const how = async (uid) => (await h.db().doc(`users/${uid}`).get()).get('pairingEndedHow');

describe('processSeparations (schedule)', () => {
  beforeEach(h.clearAll);

  it('ends only due couples, with how from the status', async () => {
    await h.seedCouple('dueAgreed', ['a1', 'a2'], sep({ status: 'agreed', agreedAt: h.ts(-8 * h.DAY), effectiveAt: h.ts(-h.DAY) }));
    await h.seedCouple('dueRequested', ['r1', 'r2'], sep({ effectiveAt: h.ts(-60 * 1000) }));
    await h.seedCouple('dueDeclined', ['d1', 'd2'], sep({ status: 'declined', declinedAt: h.ts(-10 * h.DAY) }));
    await h.seedCouple('future', ['f1', 'f2'], sep({ effectiveAt: h.ts(h.DAY) }));
    await h.seedCouple('noSeparation', ['n1', 'n2']);

    await tick();

    assert.equal(await exists('dueAgreed'), false);
    assert.equal(await exists('dueRequested'), false);
    assert.equal(await exists('dueDeclined'), false);
    assert.equal(await how('a1'), 'agreed');
    assert.equal(await how('r2'), 'oneSided');
    assert.equal(await how('d1'), 'oneSided');

    assert.equal(await exists('future'), true);
    assert.equal(await exists('noSeparation'), true);
    assert.equal((await h.db().doc('users/f1').get()).get('coupleId'), 'future');
    assert.equal((await h.db().doc('users/n1').get()).get('coupleId'), 'noSeparation');
    assert.equal((await h.listFiles('couples/future/')).length, 6);

    await tick(); // idempotent second tick
    assert.equal(await exists('future'), true);
  });
});

describe('finalizeSeparation (callable)', () => {
  beforeEach(h.clearAll);

  it('requires auth', async () => {
    await h.seedCouple('c1', ['alice', 'bob'], sep());
    await rejectsWith(call(finalizeSeparation, null, { coupleId: 'c1' }), 'unauthenticated');
  });

  it('rejects a bad coupleId', async () => {
    await rejectsWith(call(finalizeSeparation, 'alice', {}), 'invalid-argument');
    await rejectsWith(call(finalizeSeparation, 'alice', { coupleId: 'a/b' }), 'invalid-argument');
  });

  it('rejects a non-member', async () => {
    await h.seedCouple('c1', ['alice', 'bob'], sep());
    await rejectsWith(call(finalizeSeparation, 'mallory', { coupleId: 'c1' }), 'permission-denied');
    assert.equal(await exists('c1'), true);
  });

  it('rejects before effectiveAt ("not yet")', async () => {
    await h.seedCouple('c1', ['alice', 'bob'], sep({ effectiveAt: h.ts(3 * h.DAY) }));
    await rejectsWith(call(finalizeSeparation, 'alice', { coupleId: 'c1' }), 'failed-precondition', /not yet/i);
    assert.equal(await exists('c1'), true);
    assert.equal((await h.db().doc('couples/c1').get()).get('ending'), undefined, 'no lease left behind');
  });

  it('rejects when there is no separation', async () => {
    await h.seedCouple('c1');
    await rejectsWith(call(finalizeSeparation, 'bob', { coupleId: 'c1' }), 'failed-precondition');
  });

  it('ends a due couple for a member, then reports alreadyEnded', async () => {
    await h.seedCouple('c1', ['alice', 'bob'], sep({ status: 'agreed', agreedAt: h.ts(-8 * h.DAY) }));
    assert.deepEqual(await call(finalizeSeparation, 'bob', { coupleId: 'c1' }), { status: 'ended', how: 'agreed' });
    assert.equal(await exists('c1'), false);
    assert.equal(await how('alice'), 'agreed');
    assert.deepEqual(await call(finalizeSeparation, 'bob', { coupleId: 'c1' }), { status: 'alreadyEnded', how: null });
  });
});

describe('leaveNow (callable)', () => {
  beforeEach(h.clearAll);

  it('requires auth', async () => {
    await h.seedCouple('c1');
    await rejectsWith(call(leaveNow, null, { coupleId: 'c1', confirm: 'LEAVE' }), 'unauthenticated');
  });

  it('requires confirm === "LEAVE"', async () => {
    await h.seedCouple('c1');
    await rejectsWith(call(leaveNow, 'alice', { coupleId: 'c1' }), 'invalid-argument');
    await rejectsWith(call(leaveNow, 'alice', { coupleId: 'c1', confirm: 'leave' }), 'invalid-argument');
    assert.equal(await exists('c1'), true);
  });

  it('rejects a non-member', async () => {
    await h.seedCouple('c1');
    await rejectsWith(call(leaveNow, 'mallory', { coupleId: 'c1', confirm: 'LEAVE' }), 'permission-denied');
    assert.equal(await exists('c1'), true);
  });

  it('ends immediately without any separation', async () => {
    await h.seedCouple('c1');
    assert.deepEqual(await call(leaveNow, 'alice', { coupleId: 'c1', confirm: 'LEAVE' }), { status: 'ended', how: 'leftNow' });
    assert.equal(await exists('c1'), false);
    assert.equal(await how('alice'), 'leftNow');
    assert.equal(await how('bob'), 'leftNow');
  });

  it('ends immediately even when a separation is still in the future', async () => {
    await h.seedCouple('c1', ['alice', 'bob'], sep({ effectiveAt: h.ts(10 * h.DAY) }));
    assert.equal((await call(leaveNow, 'bob', { coupleId: 'c1', confirm: 'LEAVE' })).status, 'ended');
    assert.equal(await how('alice'), 'leftNow');
  });
});
