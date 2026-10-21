const assert = require('node:assert/strict');
const h = require('./helpers.js');
const { Timestamp } = require('firebase-admin/firestore');
const { endCouple, DEFAULT_LEASE_MS } = require('../lib/endCouple.js');

describe('endCouple', () => {
  beforeEach(h.clearAll);

  it('deletes every subcollection (nested + unknown), storage, backgrounds, invites, pairRequests and the root', async () => {
    await h.seedCouple('c1');
    await h.seedCouple('other', ['carol', 'dave']);
    assert.ok((await h.countDocsUnder('couples/c1')) > 15);

    const r = await endCouple('c1', 'agreed');
    assert.equal(r.status, 'ended');
    assert.equal(r.counts.subcollectionDocs.games, 3); // g1, secret/answers, deeper/x
    assert.equal(r.counts.subcollectionDocs.futureThing2030, 2);
    assert.equal(r.counts.storageFiles, 6);
    assert.equal(r.counts.backgroundFiles, 2);
    assert.equal(r.counts.invites, 1);
    assert.equal(r.counts.pairRequests, 1);
    assert.equal(r.counts.usersUpdated, 2);

    const f = h.db();
    assert.equal(await h.countDocsUnder('couples/c1'), 0);
    assert.equal((await f.doc('couples/c1/games/g1/secret/answers').get()).exists, false);
    assert.equal((await f.doc('couples/c1/ghostParent/missing/kids/k1').get()).exists, false);
    assert.equal((await f.doc('couples/c1').get()).exists, false);
    assert.equal((await f.doc('invites/INVc1').get()).exists, false);
    assert.equal((await f.doc('pairRequests/pr_c1').get()).exists, false);
    assert.deepEqual(await h.listFiles('couples/c1/'), []);
    assert.deepEqual(await h.listFiles('users/alice/backgrounds/'), []);
    assert.deepEqual(await h.listFiles('users/bob/backgrounds/'), []);
    // Kept: own profile photos.
    assert.deepEqual(await h.listFiles('users/alice/profile/'), ['users/alice/profile/me.jpg']);
    assert.deepEqual(await h.listFiles('users/bob/profile/'), ['users/bob/profile/me.jpg']);

    // The other couple is untouched.
    assert.ok((await h.countDocsUnder('couples/other')) > 15);
    assert.equal((await h.listFiles('couples/other/')).length, 6);
    assert.equal((await f.doc('invites/INVother').get()).exists, true);
    assert.equal((await f.doc('pairRequests/pr_other').get()).exists, true);
    assert.deepEqual(await h.listFiles('users/carol/backgrounds/'), ['users/carol/backgrounds/bg.jpg']);
    assert.equal((await f.doc('users/carol').get()).get('coupleId'), 'other');
  });

  it('clears couple fields, keeps profile fields, sets pairingEndedAt/how', async () => {
    await h.seedCouple('c1');
    const before = Date.now();
    await endCouple('c1', 'oneSided');
    for (const uid of ['alice', 'bob']) {
      const u = (await h.db().doc(`users/${uid}`).get()).data();
      assert.equal(u.coupleId, null);
      assert.ok('coupleId' in u, 'coupleId is set to null, not removed');
      for (const k of ['chatLookMode', 'chatLook', 'chatClearedAt', 'mutePartner']) assert.ok(!(k in u), `${k} removed`);
      assert.equal(u.pairingEndedHow, 'oneSided');
      assert.ok(u.pairingEndedAt instanceof Timestamp);
      assert.ok(u.pairingEndedAt.toMillis() >= before - 5000);
      const { displayName, ...profile } = h.PROFILE;
      assert.equal(u.displayName, uid);
      for (const [k, v] of Object.entries(profile)) assert.deepEqual(u[k], v, `${k} kept`);
    }
  });

  it('is idempotent: a second run is a no-op and does not reset pairingEndedAt', async () => {
    await h.seedCouple('c1');
    await endCouple('c1', 'agreed');
    // The app clears pairingEndedAt after showing the notice.
    await h.db().doc('users/alice').update({ pairingEndedAt: null });
    const r2 = await endCouple('c1', 'leftNow');
    assert.equal(r2.status, 'alreadyEnded');
    const a = (await h.db().doc('users/alice').get()).data();
    assert.equal(a.pairingEndedAt, null);
    assert.equal(a.pairingEndedHow, 'agreed');
  });

  it('resumes an interrupted run (expired lease) with the original how, skipping already-unpaired users', async () => {
    await h.seedCouple('c1');
    const f = h.db();
    // Simulate a crash after alice was unpaired and some data was deleted.
    await f.doc('couples/c1').update({
      ending: { how: 'agreed', startedAt: h.ts(-h.DAY), leaseExpiresAt: h.ts(-1000), attempts: 1 },
    });
    await f.doc('couples/c1/messages/a').delete();
    await f.doc('users/alice').update({ coupleId: null, pairingEndedAt: null, pairingEndedHow: 'agreed' });
    await f.doc('invites/INVc1').delete();

    const r = await endCouple('c1', 'oneSided');
    assert.equal(r.status, 'ended');
    assert.equal(r.how, 'agreed');
    assert.equal(r.counts.usersUpdated, 1);
    assert.equal(r.counts.usersSkipped, 1);
    assert.equal(r.counts.invites, 0);
    assert.equal((await f.doc('couples/c1').get()).exists, false);
    assert.equal((await f.doc('users/alice').get()).get('pairingEndedAt'), null); // not re-shown
    assert.equal((await f.doc('users/bob').get()).get('pairingEndedHow'), 'agreed');
  });

  it('does not touch a member who already re-paired with someone else', async () => {
    await h.seedCouple('c1');
    await h.db().doc('users/alice').update({ coupleId: 'newCouple', chatLookMode: 'mine' });
    await endCouple('c1', 'agreed');
    const a = (await h.db().doc('users/alice').get()).data();
    assert.equal(a.coupleId, 'newCouple');
    assert.equal(a.chatLookMode, 'mine');
    assert.ok(!('pairingEndedAt' in a));
    assert.deepEqual(await h.listFiles('users/alice/backgrounds/'), ['users/alice/backgrounds/bg.jpg']);
  });

  it('handles a member whose user doc is missing', async () => {
    await h.seedCouple('c1');
    await h.db().doc('users/bob').delete();
    const r = await endCouple('c1', 'agreed');
    assert.equal(r.status, 'ended');
    assert.equal(r.counts.usersUpdated, 1);
    assert.equal(r.counts.usersMissing, 1);
    assert.equal((await h.db().doc('users/bob').get()).exists, false, 'no doc is created');
    assert.deepEqual(await h.listFiles('users/bob/backgrounds/'), []);
  });

  it('handles a couple that is already deleted', async () => {
    const r = await endCouple('nope', 'agreed');
    assert.deepEqual(r, { status: 'alreadyEnded', how: undefined });
  });

  it('concurrent runs on one couple: exactly one does the work', async () => {
    await h.seedCouple('c1');
    const results = await Promise.all([endCouple('c1', 'agreed'), endCouple('c1', 'leftNow'), endCouple('c1', 'oneSided')]);
    const statuses = results.map((r) => r.status).sort();
    assert.equal(statuses.filter((s) => s === 'ended').length, 1, JSON.stringify(statuses));
    const winner = results.find((r) => r.status === 'ended');
    assert.equal((await h.db().doc('users/alice').get()).get('pairingEndedHow'), winner.how);
    assert.equal((await h.db().doc('couples/c1').get()).exists, false);
  });

  it('a live lease makes other callers back off without changing anything', async () => {
    await h.seedCouple('c1');
    await h.db().doc('couples/c1').update({
      ending: { how: 'oneSided', startedAt: h.ts(0), leaseExpiresAt: h.ts(DEFAULT_LEASE_MS), attempts: 1 },
    });
    const r = await endCouple('c1', 'leftNow');
    assert.deepEqual(r, { status: 'inProgress', how: 'oneSided' });
    assert.ok((await h.countDocsUnder('couples/c1')) > 15);
    assert.equal((await h.db().doc('users/alice').get()).get('coupleId'), 'c1');
  });
});
