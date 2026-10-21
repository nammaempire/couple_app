// Rules for new-phone sign-in protection: known phones, partner checks and
// security notices.
const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment, assertSucceeds, assertFails,
} = require('@firebase/rules-unit-testing');
const {
  doc, getDoc, getDocs, setDoc, addDoc, updateDoc, deleteDoc, collection,
  serverTimestamp, Timestamp,
} = require('firebase/firestore');

const C = 'couple1';
let env;
const dbs = {};
const db = (uid) => (dbs[uid] ||= env.authenticatedContext(uid).firestore());
const device = (o = {}) => ({ name: 'Pixel 9', addedAt: serverTimestamp(), lastSeenAt: serverTimestamp(), via: 'partner', ...o });

describe('device check rules', () => {
  before(async () => {
    env = await initializeTestEnvironment({
      projectId: 'demo-couple',
      firestore: {
        rules: fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8'),
        host: '127.0.0.1', port: 8085,
      },
    });
  });
  after(async () => env && env.cleanup());
  beforeEach(async () => {
    for (const k of Object.keys(dbs)) delete dbs[k];
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (c) => {
      const f = c.firestore();
      await setDoc(doc(f, `couples/${C}`), { memberIds: ['alice', 'bob'], inviteCode: 'ABC234' });
      await setDoc(doc(f, 'users/alice'), { displayName: 'Alice', coupleId: C });
      await setDoc(doc(f, 'users/bob'), { displayName: 'Bob', coupleId: C });
      await setDoc(doc(f, 'users/carol'), { displayName: 'Carol', coupleId: null });
    });
  });

  it('known phones: the owner records them, only lastSeenAt moves', async () => {
    const d = (uid) => doc(db(uid), 'users/alice/devices/dev1');
    await assertSucceeds(setDoc(d('alice'), device({ via: 'first' })));
    await assertFails(setDoc(doc(db('alice'), 'users/alice/devices/dev2'), device({ via: 'trustme' })));
    await assertFails(setDoc(doc(db('bob'), 'users/alice/devices/dev3'), device()));
    await assertSucceeds(updateDoc(d('alice'), { lastSeenAt: serverTimestamp() }));
    await assertFails(updateDoc(d('alice'), { via: 'email' }));
    await assertSucceeds(getDoc(d('bob')));
    await assertFails(getDoc(d('carol')));
    await assertFails(deleteDoc(d('bob')));
    await assertSucceeds(deleteDoc(d('alice')));
  });

  it('a new-phone check: the other partner decides, once', async () => {
    const r = await assertSucceeds(addDoc(collection(db('alice'), `couples/${C}/deviceChecks`), {
      uid: 'alice', deviceId: 'dev9', deviceName: 'Pixel 9', createdAt: serverTimestamp(), status: 'pending', code: 47,
    }));
    await assertFails(addDoc(collection(db('alice'), `couples/${C}/deviceChecks`), {
      uid: 'alice', deviceId: 'dev9', deviceName: 'Pixel 9', createdAt: serverTimestamp(), status: 'approved', code: 47,
    }));
    await assertFails(addDoc(collection(db('alice'), `couples/${C}/deviceChecks`), {
      uid: 'bob', deviceId: 'dev9', deviceName: 'Pixel 9', createdAt: serverTimestamp(), status: 'pending', code: 47,
    }));
    const check = (uid) => doc(db(uid), `couples/${C}/deviceChecks/${r.id}`);
    // The person on the new phone can't approve themselves.
    await assertFails(updateDoc(check('alice'), { status: 'approved', decidedBy: 'alice', decidedAt: serverTimestamp() }));
    await assertFails(updateDoc(check('bob'), { status: 'approved', decidedBy: 'alice', decidedAt: serverTimestamp() }));
    await assertFails(getDoc(check('carol')));
    await assertSucceeds(updateDoc(check('bob'), { status: 'approved', decidedBy: 'bob', decidedAt: serverTimestamp() }));
    await assertFails(updateDoc(check('bob'), { status: 'rejected', decidedBy: 'bob', decidedAt: serverTimestamp() }));
    await assertFails(deleteDoc(check('bob')));
    await assertSucceeds(deleteDoc(check('alice')));
  });

  it('security notices: the owner, or the partner saying they turned a phone down', async () => {
    const ev = (o = {}) => ({ type: 'newPhoneRejected', deviceName: 'Pixel 9', at: serverTimestamp(), ...o });
    await assertSucceeds(addDoc(collection(db('alice'), 'users/alice/securityEvents'), ev({ type: 'newPhoneWaiting' })));
    await assertSucceeds(addDoc(collection(db('bob'), 'users/alice/securityEvents'), ev()));
    await assertFails(addDoc(collection(db('bob'), 'users/alice/securityEvents'), ev({ type: 'newPhoneApproved' })));
    await assertFails(addDoc(collection(db('carol'), 'users/alice/securityEvents'), ev()));
    await assertSucceeds(getDocs(collection(db('alice'), 'users/alice/securityEvents')));
    await assertFails(getDocs(collection(db('bob'), 'users/alice/securityEvents')));
  });

  it('the owner can pause new-phone sign-ins', async () => {
    await assertSucceeds(updateDoc(doc(db('alice'), 'users/alice'), { blockNewPhoneUntil: Timestamp.fromMillis(Date.now() + 30 * 86400000) }));
    await assertFails(updateDoc(doc(db('alice'), 'users/alice'), { blockNewPhoneUntil: 'forever' }));
    await assertFails(updateDoc(doc(db('bob'), 'users/alice'), { blockNewPhoneUntil: Timestamp.now() }));
  });
});
