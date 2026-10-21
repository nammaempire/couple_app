// Rules for the end-to-end encrypted vault: shape and membership only, since
// the server never sees anything readable.
const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment, assertSucceeds, assertFails,
} = require('@firebase/rules-unit-testing');
const {
  doc, getDoc, setDoc, addDoc, updateDoc, deleteDoc, collection,
  serverTimestamp, Timestamp, deleteField,
} = require('firebase/firestore');
const { ref, uploadBytes, getBytes, deleteObject } = require('firebase/storage');

const C = 'couple1';
let env;
const dbs = {};
const db = (uid) => (dbs[uid] ||= env.authenticatedContext(uid).firestore());
const st = (uid) => env.authenticatedContext(uid).storage();
const meta = (uid) => doc(db(uid), `couples/${C}/vault/meta`);
const items = (uid) => collection(db(uid), `couples/${C}/vaultItems`);

const metaDoc = (o = {}) => ({
  version: 1, createdBy: 'alice', createdAt: serverTimestamp(),
  devices: { d1: { uid: 'alice', publicKey: 'cHVi', name: 'Pixel 8', approved: true, addedAt: Timestamp.now() } },
  keys: { d1: { vmk: 'd3JhcA==', dk: 'd3JhcA==' } },
  verifier: 'Y2lwaGVy', updatedBy: 'alice', updatedAt: serverTimestamp(), ...o,
});
const item = (o = {}) => ({
  senderId: 'alice', kind: 'message', shelf: 'a', ct: 'Y2lwaGVy',
  photoPath: null, thumbPath: null, policy: 'keep', expiresAt: null,
  viewedBy: {}, createdAt: serverTimestamp(), ...o,
});

describe('vault rules', () => {
  before(async () => {
    env = await initializeTestEnvironment({
      projectId: 'demo-couple',
      firestore: {
        rules: fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8'),
        host: '127.0.0.1', port: 8085,
      },
      storage: {
        rules: fs.readFileSync(path.join(__dirname, '../../storage.rules'), 'utf8'),
        host: '127.0.0.1', port: 9199,
      },
    });
  });
  after(async () => env && env.cleanup());
  beforeEach(async () => {
    for (const k of Object.keys(dbs)) delete dbs[k];
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `couples/${C}`), { memberIds: ['alice', 'bob'], inviteCode: 'ABC234' });
    });
  });

  describe('meta', () => {
    it('a member sets it up; the partner reads, registers a phone and gets approved', async () => {
      await assertSucceeds(setDoc(meta('alice'), metaDoc()));
      await assertSucceeds(getDoc(meta('bob')));
      await assertSucceeds(updateDoc(meta('bob'), {
        'devices.d2': { uid: 'bob', publicKey: 'cHViMg==', name: 'Galaxy', approved: false, addedAt: Timestamp.now() },
        updatedBy: 'bob', updatedAt: serverTimestamp(),
      }));
      await assertSucceeds(updateDoc(meta('alice'), {
        'devices.d2.approved': true, 'keys.d2': { vmk: 'eA==', dk: 'eA==' },
        updatedBy: 'alice', updatedAt: serverTimestamp(),
      }));
    });

    it('strangers cannot read or write it; shape is checked', async () => {
      await assertFails(setDoc(meta('carol'), metaDoc({ createdBy: 'carol', updatedBy: 'carol' })));
      await assertSucceeds(setDoc(meta('alice'), metaDoc()));
      await assertFails(getDoc(meta('carol')));
      await assertFails(updateDoc(meta('alice'), { verifier: 'x'.repeat(4001), updatedBy: 'alice', updatedAt: serverTimestamp() }));
      await assertFails(updateDoc(meta('alice'), { verifier: 'y', updatedBy: 'bob', updatedAt: serverTimestamp() }));
      await assertFails(updateDoc(meta('alice'), { verifier: 'y', updatedBy: 'alice' }));
      await assertFails(updateDoc(meta('bob'), { createdBy: 'bob', updatedBy: 'bob', updatedAt: serverTimestamp() }));
      await assertFails(setDoc(doc(db('alice'), `couples/${C}/vault/other`), metaDoc()));
    });

    it('either partner can wipe it', async () => {
      await assertSucceeds(setDoc(meta('alice'), metaDoc()));
      await assertFails(deleteDoc(meta('carol')));
      await assertSucceeds(deleteDoc(meta('bob')));
    });
  });

  describe('items', () => {
    it('messages and photos: sent as yourself, shape checked', async () => {
      await assertSucceeds(addDoc(items('alice'), item()));
      await assertSucceeds(addDoc(items('alice'), item({
        kind: 'photo', shelf: 'b',
        photoPath: `couples/${C}/vault/p1`, thumbPath: `couples/${C}/vault/t1`,
      })));
      await assertFails(addDoc(items('alice'), item({ senderId: 'bob' })));
      await assertFails(addDoc(items('alice'), item({ shelf: 'real' })));
      await assertFails(addDoc(items('alice'), item({ kind: 'video' })));
      await assertFails(addDoc(items('alice'), item({ ct: '' })));
      await assertFails(addDoc(items('alice'), item({ ct: 'x'.repeat(20001) })));
      await assertFails(addDoc(items('alice'), item({ photoPath: 'couples/other/vault/p1' })));
      await assertFails(addDoc(items('alice'), item({ viewedBy: { bob: Timestamp.now() } })));
      await assertFails(addDoc(items('carol'), item({ senderId: 'carol' })));
    });

    it('24-hour items need a sensible expiry; others none', async () => {
      const in24h = Timestamp.fromMillis(Date.now() + 24 * 3600 * 1000);
      await assertSucceeds(addDoc(items('alice'), item({ policy: 'day', expiresAt: in24h })));
      await assertFails(addDoc(items('alice'), item({ policy: 'day', expiresAt: null })));
      await assertFails(addDoc(items('alice'), item({ policy: 'day', expiresAt: Timestamp.fromMillis(Date.now() + 30 * 86400000) })));
      await assertFails(addDoc(items('alice'), item({ policy: 'keep', expiresAt: in24h })));
      await assertSucceeds(addDoc(items('alice'), item({ policy: 'once' })));
    });

    it('only your own "viewed" mark can change; either partner deletes', async () => {
      const r = await addDoc(items('alice'), item({ policy: 'once' }));
      const bobRef = doc(db('bob'), `couples/${C}/vaultItems/${r.id}`);
      await assertSucceeds(updateDoc(bobRef, { 'viewedBy.bob': serverTimestamp() }));
      await assertFails(updateDoc(bobRef, { 'viewedBy.alice': serverTimestamp() }));
      await assertFails(updateDoc(bobRef, { ct: 'dGFtcGVy' }));
      await assertFails(getDoc(doc(db('carol'), `couples/${C}/vaultItems/${r.id}`)));
      await assertSucceeds(deleteDoc(bobRef));
    });
  });

  describe('events', () => {
    it('alerts are written as yourself; partner reads and dismisses', async () => {
      const ev = { type: 'wrongCode', uid: 'alice', deviceName: 'Pixel 8', at: serverTimestamp() };
      const r = await assertSucceeds(addDoc(collection(db('alice'), `couples/${C}/vaultEvents`), ev));
      await assertFails(addDoc(collection(db('alice'), `couples/${C}/vaultEvents`), { ...ev, uid: 'bob' }));
      await assertFails(addDoc(collection(db('alice'), `couples/${C}/vaultEvents`), { ...ev, type: 'opened' }));
      await assertFails(updateDoc(doc(db('bob'), `couples/${C}/vaultEvents/${r.id}`), { type: 'cooldown' }));
      await assertSucceeds(getDoc(doc(db('bob'), `couples/${C}/vaultEvents/${r.id}`)));
      await assertSucceeds(deleteDoc(doc(db('bob'), `couples/${C}/vaultEvents/${r.id}`)));
    });
  });

  describe('storage', () => {
    it('encrypted bytes only, members only', async () => {
      const bytes = new Uint8Array([1, 2, 3, 4]);
      const mine = ref(st('alice'), `couples/${C}/vault/p1`);
      await assertSucceeds(uploadBytes(mine, bytes, { contentType: 'application/octet-stream' }));
      await assertSucceeds(getBytes(ref(st('bob'), `couples/${C}/vault/p1`)));
      await assertFails(getBytes(ref(st('carol'), `couples/${C}/vault/p1`)));
      await assertFails(uploadBytes(ref(st('alice'), `couples/${C}/vault/p2`), bytes, { contentType: 'image/jpeg' }));
      await assertFails(uploadBytes(ref(st('carol'), `couples/${C}/vault/p3`), bytes, { contentType: 'application/octet-stream' }));
      await assertSucceeds(deleteObject(ref(st('bob'), `couples/${C}/vault/p1`)));
    });
  });
});
