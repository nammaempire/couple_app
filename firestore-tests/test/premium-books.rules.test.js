// Rules for Premium (server-granted), gifts and Memory books (one credit
// each).
const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment, assertSucceeds, assertFails,
} = require('@firebase/rules-unit-testing');
const {
  doc, getDoc, setDoc, updateDoc, deleteDoc, writeBatch, increment,
  serverTimestamp, Timestamp,
} = require('firebase/firestore');
const { ref, uploadBytes, getBytes } = require('firebase/storage');

const C = 'couple1';
let env;
const dbs = {};
const db = (uid) => (dbs[uid] ||= env.authenticatedContext(uid).firestore());
const couple = (uid) => doc(db(uid), `couples/${C}`);
const book = (uid, id = 'b1', o = {}) => ({
  createdBy: uid, title: 'Asha & Ravi · 2026',
  fromDate: Timestamp.fromDate(new Date('2026-01-01')), toDate: Timestamp.fromDate(new Date('2026-12-31')),
  pageCount: 34, storagePath: `couples/${C}/books/${id}.pdf`, createdAt: serverTimestamp(), ...o,
});
const spend = (uid, id = 'b1', o = {}, step = -1) => {
  const b = writeBatch(db(uid));
  b.update(couple(uid), { bookCredits: increment(step) });
  b.set(doc(db(uid), `couples/${C}/books/${id}`), book(uid, id, o));
  return b.commit();
};

describe('premium, gifts and books rules', () => {
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
    await env.withSecurityRulesDisabled(async (c) => {
      const f = c.firestore();
      await setDoc(doc(f, `couples/${C}`), { memberIds: ['alice', 'bob'], inviteCode: 'ABC234', bookCredits: 1 });
      await setDoc(doc(f, `couples/${C}/gifts/g1`), { fromUid: 'alice', toUid: 'bob', kind: 'premium', months: 3, message: 'For you', createdAt: Timestamp.now(), openedAt: null });
      await setDoc(doc(f, 'purchases/h1'), { coupleId: C, uid: 'alice' });
    });
  });

  it('Premium can only come from the server', async () => {
    await assertFails(updateDoc(couple('alice'), { premium: { until: Timestamp.fromMillis(Date.now() + 1e10), plan: 'yearly' } }));
    await assertFails(updateDoc(couple('alice'), { bookCredits: 5 }));
    await assertFails(updateDoc(couple('alice'), { bookCredits: increment(1) }));
    await assertFails(getDoc(doc(db('alice'), 'purchases/h1')));
    await assertFails(setDoc(doc(db('alice'), 'purchases/h2'), { coupleId: C }));
  });

  it('a book costs exactly one credit, in the same batch', async () => {
    await assertFails(setDoc(doc(db('alice'), `couples/${C}/books/b1`), book('alice'))); // no credit spent
    await assertFails(spend('alice', 'b1', {}, -2));
    await assertFails(spend('alice', 'b1', { createdBy: 'bob' }));
    await assertFails(spend('alice', 'b1', { storagePath: `couples/${C}/books/other.pdf` }));
    await assertFails(spend('alice', 'b1', { title: '' }));
    await assertSucceeds(spend('alice'));
    await assertSucceeds(getDoc(doc(db('bob'), `couples/${C}/books/b1`)));
    await assertFails(spend('alice', 'b2')); // no credits left
    await assertFails(updateDoc(couple('alice'), { bookCredits: increment(-1) })); // never below zero
  });

  it('the maker renames; either deletes; strangers see nothing', async () => {
    await assertSucceeds(spend('alice'));
    const b = (uid) => doc(db(uid), `couples/${C}/books/b1`);
    await assertSucceeds(updateDoc(b('alice'), { title: 'Our first year' }));
    await assertFails(updateDoc(b('bob'), { title: 'Mine' }));
    await assertFails(updateDoc(b('alice'), { pageCount: 99 }));
    await assertFails(getDoc(b('carol')));
    await assertSucceeds(deleteDoc(b('bob')));
  });

  it('a gift is opened once, by the partner it is for', async () => {
    const g = (uid) => doc(db(uid), `couples/${C}/gifts/g1`);
    await assertSucceeds(getDoc(g('alice')));
    await assertFails(setDoc(doc(db('alice'), `couples/${C}/gifts/g2`), { fromUid: 'alice', toUid: 'bob', kind: 'premium' }));
    await assertFails(updateDoc(g('alice'), { openedAt: serverTimestamp() }));
    await assertFails(updateDoc(g('bob'), { openedAt: serverTimestamp(), months: 12 }));
    await assertSucceeds(updateDoc(g('bob'), { openedAt: serverTimestamp() }));
    await assertFails(updateDoc(g('bob'), { openedAt: serverTimestamp() }));
    await assertFails(deleteDoc(g('bob')));
  });

  it('book PDFs: members only, PDFs only', async () => {
    const st = (uid) => env.authenticatedContext(uid).storage();
    const bytes = new Uint8Array([37, 80, 68, 70]);
    await assertSucceeds(uploadBytes(ref(st('alice'), `couples/${C}/books/b1.pdf`), bytes, { contentType: 'application/pdf' }));
    await assertSucceeds(getBytes(ref(st('bob'), `couples/${C}/books/b1.pdf`)));
    await assertFails(getBytes(ref(st('carol'), `couples/${C}/books/b1.pdf`)));
    await assertFails(uploadBytes(ref(st('alice'), `couples/${C}/books/b2.pdf`), bytes, { contentType: 'image/png' }));
  });
});
