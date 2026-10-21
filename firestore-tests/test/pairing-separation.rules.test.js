// Rules for mobile-number pairing (phoneIndex, pairRequests) and ending a
// pairing (couples/{id}.separation), with the vault closed while it ends.
const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment, assertSucceeds, assertFails,
} = require('@firebase/rules-unit-testing');
const {
  doc, getDoc, getDocs, setDoc, addDoc, updateDoc, deleteDoc, collection,
  query, where, serverTimestamp, Timestamp, deleteField,
} = require('firebase/firestore');

const C = 'couple1';
const DAY = 86400000;
let env;
const dbs = {};
const ctx = (uid, phone) => (phone
  ? env.authenticatedContext(uid, { phone_number: phone })
  : env.authenticatedContext(uid));
const db = (uid, phone) => (dbs[uid + (phone || '')] ||= ctx(uid, phone).firestore());
const couple = (uid) => doc(db(uid), `couples/${C}`);
const at = (ms) => Timestamp.fromMillis(Date.now() + ms);

const request = (o = {}) => ({
  requestedBy: 'alice', requestedAt: serverTimestamp(), status: 'requested',
  agreedAt: null, declinedAt: null, effectiveAt: at(14 * DAY), ...o,
});

describe('pairing and separation rules', () => {
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
      await setDoc(doc(f, 'couples/solo'), { memberIds: ['carol'], inviteCode: 'SOLO23' });
      await setDoc(doc(f, 'users/alice'), { displayName: 'Alice', coupleId: C });
      await setDoc(doc(f, 'users/carol'), { displayName: 'Carol', coupleId: 'solo' });
      await setDoc(doc(f, `couples/${C}/vault/meta`), { version: 1 });
    });
  });

  describe('phone numbers', () => {
    it('only the verified owner claims a number; anyone signed in can look one up, nobody can list', async () => {
      const mine = doc(db('alice', '+919876543210'), 'phoneIndex/+919876543210');
      await assertSucceeds(setDoc(mine, { uid: 'alice', createdAt: serverTimestamp() }));
      await assertFails(setDoc(doc(db('bob', '+919000000001'), 'phoneIndex/+919876543210'), { uid: 'bob', createdAt: serverTimestamp() }));
      await assertFails(setDoc(doc(db('dave'), 'phoneIndex/+919111111111'), { uid: 'dave', createdAt: serverTimestamp() }));
      await assertFails(setDoc(doc(db('alice', '+919876543210'), 'phoneIndex/+919876543210'), { uid: 'bob', createdAt: serverTimestamp() }));
      await assertSucceeds(getDoc(doc(db('carol'), 'phoneIndex/+919876543210')));
      await assertFails(getDocs(collection(db('carol'), 'phoneIndex')));
    });

    it('a recycled number moves to whoever verifies it now', async () => {
      await assertSucceeds(setDoc(doc(db('alice', '+919876543210'), 'phoneIndex/+919876543210'), { uid: 'alice', createdAt: serverTimestamp() }));
      await assertSucceeds(setDoc(doc(db('erin', '+919876543210'), 'phoneIndex/+919876543210'), { uid: 'erin', createdAt: serverTimestamp() }));
    });

    it('a profile phone must be the verified one; mute is a bool; ended-markers can only be cleared', async () => {
      await assertSucceeds(updateDoc(doc(db('alice', '+919876543210'), 'users/alice'), { phone: '+919876543210', mutePartner: true }));
      await assertFails(updateDoc(doc(db('alice', '+919876543210'), 'users/alice'), { phone: '+919000000000' }));
      await assertFails(updateDoc(doc(db('alice'), 'users/alice'), { mutePartner: 'yes' }));
      await assertFails(updateDoc(doc(db('alice'), 'users/alice'), { pairingEndedAt: serverTimestamp() }));
      await env.withSecurityRulesDisabled((c) => updateDoc(doc(c.firestore(), 'users/alice'), { pairingEndedAt: Timestamp.now(), pairingEndedHow: 'agreed' }));
      await assertFails(updateDoc(doc(db('alice'), 'users/alice'), { pairingEndedHow: 'leftNow' }));
      await assertSucceeds(updateDoc(doc(db('alice'), 'users/alice'), { pairingEndedAt: deleteField(), pairingEndedHow: deleteField() }));
    });
  });

  describe('pair requests', () => {
    const req = (o = {}) => ({
      fromUid: 'carol', fromName: 'Carol', fromPhone: '+919000000003', toUid: 'dave',
      toPhone: '+919000000004', coupleId: 'solo', inviteCode: 'SOLO23',
      status: 'pending', createdAt: serverTimestamp(), ...o,
    });

    it('sent from your own couple of one, with its real code', async () => {
      await assertSucceeds(addDoc(collection(db('carol'), 'pairRequests'), req()));
      await assertSucceeds(addDoc(collection(db('carol'), 'pairRequests'), req({ fromPhone: '' })));
      await assertFails(addDoc(collection(db('carol'), 'pairRequests'), req({ inviteCode: 'WRONG1' })));
      await assertFails(addDoc(collection(db('carol'), 'pairRequests'), req({ fromUid: 'dave' })));
      await assertFails(addDoc(collection(db('carol'), 'pairRequests'), req({ toUid: 'carol' })));
      await assertFails(addDoc(collection(db('carol'), 'pairRequests'), req({ status: 'accepted' })));
      await assertFails(addDoc(collection(db('carol'), 'pairRequests'), req({ toPhone: '98765' })));
      // Alice is already in a couple of two: she can't offer it.
      await assertFails(addDoc(collection(db('alice'), 'pairRequests'), req({ fromUid: 'alice', coupleId: C, inviteCode: 'ABC234' })));
    });

    it('only the two people involved see it; the receiver answers, the sender cancels, once', async () => {
      const r = await addDoc(collection(db('carol'), 'pairRequests'), req());
      await assertSucceeds(getDocs(query(collection(db('dave'), 'pairRequests'), where('toUid', '==', 'dave'), where('status', '==', 'pending'))));
      await assertFails(getDoc(doc(db('erin'), `pairRequests/${r.id}`)));
      await assertFails(updateDoc(doc(db('carol'), `pairRequests/${r.id}`), { status: 'accepted' }));
      await assertFails(updateDoc(doc(db('dave'), `pairRequests/${r.id}`), { status: 'accepted', toUid: 'erin' }));
      await assertSucceeds(updateDoc(doc(db('dave'), `pairRequests/${r.id}`), { status: 'declined' }));
      await assertFails(updateDoc(doc(db('dave'), `pairRequests/${r.id}`), { status: 'accepted' }));
      const r2 = await addDoc(collection(db('carol'), 'pairRequests'), req());
      await assertSucceeds(updateDoc(doc(db('carol'), `pairRequests/${r2.id}`), { status: 'cancelled' }));
      await assertFails(deleteDoc(doc(db('dave'), `pairRequests/${r2.id}`)));
      await assertSucceeds(deleteDoc(doc(db('carol'), `pairRequests/${r2.id}`)));
    });
  });

  describe('ending a pairing', () => {
    it('either asks, with the 14-day date; only the asker can cancel', async () => {
      await assertFails(updateDoc(couple('alice'), { separation: request({ effectiveAt: at(3 * DAY) }) }));
      await assertFails(updateDoc(couple('alice'), { separation: request({ requestedBy: 'bob' }) }));
      await assertFails(updateDoc(couple('alice'), { separation: request({ status: 'agreed' }) }));
      await assertFails(updateDoc(doc(db('carol'), `couples/${C}`), { separation: request({ requestedBy: 'carol' }) }));
      await assertSucceeds(updateDoc(couple('alice'), { separation: request() }));
      await assertFails(updateDoc(couple('alice'), { separation: request() })); // already asked
      await assertFails(updateDoc(couple('bob'), { separation: deleteField() }));
      await assertSucceeds(updateDoc(couple('alice'), { separation: deleteField() }));
    });

    it('the partner agrees: 7 days from now, never later than the original date', async () => {
      await assertSucceeds(updateDoc(couple('alice'), { separation: request() }));
      await assertFails(updateDoc(couple('alice'), { 'separation.status': 'agreed', 'separation.agreedAt': serverTimestamp(), 'separation.effectiveAt': at(7 * DAY) }));
      await assertFails(updateDoc(couple('bob'), { 'separation.status': 'agreed', 'separation.agreedAt': serverTimestamp(), 'separation.effectiveAt': at(1 * DAY) }));
      await assertSucceeds(updateDoc(couple('bob'), { 'separation.status': 'agreed', 'separation.agreedAt': serverTimestamp(), 'separation.effectiveAt': at(7 * DAY) }));
    });

    it('agreeing late keeps the earlier original date', async () => {
      await env.withSecurityRulesDisabled((c) => updateDoc(doc(c.firestore(), `couples/${C}`), {
        separation: { requestedBy: 'alice', requestedAt: Timestamp.fromMillis(Date.now() - 12 * DAY), status: 'requested', agreedAt: null, declinedAt: null, effectiveAt: at(2 * DAY) },
      }));
      const orig = (await getDoc(couple('bob'))).data().separation.effectiveAt;
      await assertFails(updateDoc(couple('bob'), { 'separation.status': 'agreed', 'separation.agreedAt': serverTimestamp(), 'separation.effectiveAt': at(7 * DAY) }));
      await assertSucceeds(updateDoc(couple('bob'), { 'separation.status': 'agreed', 'separation.agreedAt': serverTimestamp(), 'separation.effectiveAt': orig }));
    });

    it('declining changes nothing else, can be followed by agreeing, and never stops it', async () => {
      await assertSucceeds(updateDoc(couple('alice'), { separation: request() }));
      await assertFails(updateDoc(couple('bob'), { 'separation.status': 'declined', 'separation.declinedAt': serverTimestamp(), 'separation.effectiveAt': at(60 * DAY) }));
      await assertSucceeds(updateDoc(couple('bob'), { 'separation.status': 'declined', 'separation.declinedAt': serverTimestamp() }));
      await assertFails(updateDoc(couple('bob'), { separation: deleteField() }));
      await assertFails(updateDoc(couple('bob'), { 'separation.requestedBy': 'bob' }));
      await assertSucceeds(updateDoc(couple('bob'), { 'separation.status': 'agreed', 'separation.agreedAt': serverTimestamp(), 'separation.effectiveAt': at(7 * DAY) }));
    });

    it("only the server's deletion lock may be written as `ending`", async () => {
      await assertFails(updateDoc(couple('alice'), { ending: { how: 'leftNow' } }));
    });

    it('other couple changes still work while it is ending', async () => {
      await assertSucceeds(updateDoc(couple('alice'), { separation: request() }));
      await assertSucceeds(updateDoc(couple('bob'), { coupleName: 'Us', blockScreenshots: true }));
    });

    it('the vault is closed for both while it is ending', async () => {
      await assertSucceeds(getDoc(doc(db('bob'), `couples/${C}/vault/meta`)));
      await assertSucceeds(updateDoc(couple('alice'), { separation: request() }));
      await assertFails(getDoc(doc(db('bob'), `couples/${C}/vault/meta`)));
      await assertFails(getDoc(doc(db('alice'), `couples/${C}/vault/meta`)));
      await assertFails(addDoc(collection(db('alice'), `couples/${C}/vaultItems`), {
        senderId: 'alice', kind: 'message', shelf: 'a', ct: 'eA==', photoPath: null, thumbPath: null,
        policy: 'keep', expiresAt: null, viewedBy: {}, createdAt: serverTimestamp(),
      }));
      await assertFails(addDoc(collection(db('alice'), `couples/${C}/vaultEvents`), { type: 'wrongCode', uid: 'alice', deviceName: 'x', at: serverTimestamp() }));
      await assertSucceeds(updateDoc(couple('alice'), { separation: deleteField() }));
      await assertSucceeds(getDoc(doc(db('bob'), `couples/${C}/vault/meta`)));
    });
  });
});
