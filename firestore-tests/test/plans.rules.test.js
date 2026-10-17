const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment, assertSucceeds, assertFails,
} = require('@firebase/rules-unit-testing');
const {
  doc, getDoc, setDoc, updateDoc, deleteDoc, collection, query, where,
  getDocs, Timestamp,
} = require('firebase/firestore');

const C = 'couple1';
let env;
const ts = () => Timestamp.fromDate(new Date('2026-10-15T10:00:00Z'));
const db = (uid) => env.authenticatedContext(uid).firestore();
const base = (uid) => `couples/${C}`;


// scoped-hooks: keep this file's before/beforeEach from running for other files.
describe('plans rules', () => {
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
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const d = ctx.firestore();
    await setDoc(doc(d, `couples/${C}`), { memberIds: ['alice', 'bob'], inviteCode: 'ABC234' });
    await setDoc(doc(d, `couples/${C}/wishlist/w1`), {
      title: 'Kindle', notes: '', url: '', priceMinor: 1299900, priority: 'love',
      occasion: 'birthday', received: false, createdBy: 'bob',
    });
  });
});

describe('date plans', () => {
  const plan = (o = {}) => ({
    title: 'Sunset picnic', notes: '', status: 'idea', scheduledAt: null,
    location: 'Cubbon Park', estimatedCostMinor: 50000, vibe: 'outdoors',
    rating: null, reflection: '', createdBy: 'alice', completedAt: null, ...o,
  });
  it('members create, read, edit and delete', async () => {
    await assertSucceeds(setDoc(doc(db('alice'), `${base()}/datePlans/p1`), plan()));
    await assertSucceeds(getDoc(doc(db('bob'), `${base()}/datePlans/p1`)));
    await assertSucceeds(updateDoc(doc(db('bob'), `${base()}/datePlans/p1`), { status: 'planned', scheduledAt: ts() }));
    await assertSucceeds(deleteDoc(doc(db('bob'), `${base()}/datePlans/p1`)));
  });
  it('strangers are refused', async () => {
    await assertFails(setDoc(doc(db('eve'), `${base()}/datePlans/p1`), plan({ createdBy: 'eve' })));
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), `${base()}/datePlans/p1`), plan()));
    await assertFails(getDoc(doc(db('eve'), `${base()}/datePlans/p1`)));
  });
  it('rejects bad shapes', async () => {
    const r = (o) => setDoc(doc(db('alice'), `${base()}/datePlans/x`), plan(o));
    await assertFails(r({ title: '' }));
    await assertFails(r({ status: 'planned', scheduledAt: null }));
    await assertFails(r({ rating: 6 }));
    await assertFails(r({ vibe: 'weird' }));
    await assertFails(r({ createdBy: 'bob' }));
    await assertFails(r({ estimatedCostMinor: -1 }));
  });
  it('cannot change who added it', async () => {
    await assertSucceeds(setDoc(doc(db('alice'), `${base()}/datePlans/p1`), plan()));
    await assertFails(updateDoc(doc(db('bob'), `${base()}/datePlans/p1`), { createdBy: 'bob' }));
  });
});

describe('bucket list', () => {
  const item = (o = {}) => ({
    title: 'See the northern lights', notes: '', category: 'travel', done: false,
    doneAt: null, doneBy: null, targetYear: 2027, createdBy: 'alice', ...o,
  });
  it('members add and tick items', async () => {
    await assertSucceeds(setDoc(doc(db('alice'), `${base()}/bucketList/b1`), item()));
    await assertSucceeds(updateDoc(doc(db('bob'), `${base()}/bucketList/b1`), { done: true, doneAt: ts(), doneBy: 'bob' }));
  });
  it('doneBy must be a member; category must be known', async () => {
    await assertFails(setDoc(doc(db('alice'), `${base()}/bucketList/b2`), item({ done: true, doneBy: 'eve' })));
    await assertFails(setDoc(doc(db('alice'), `${base()}/bucketList/b3`), item({ category: 'nope' })));
  });
});

describe('wishlist', () => {
  const wish = (o = {}) => ({
    title: 'Film camera', notes: '', url: 'https://example.com/cam', priceMinor: 2500000,
    priority: 'like', occasion: 'any', received: false, createdBy: 'alice', ...o,
  });
  it('only the owner edits their wishes; both can read', async () => {
    await assertSucceeds(setDoc(doc(db('alice'), `${base()}/wishlist/a1`), wish()));
    await assertSucceeds(getDoc(doc(db('bob'), `${base()}/wishlist/a1`)));
    await assertFails(updateDoc(doc(db('bob'), `${base()}/wishlist/a1`), { title: 'Changed' }));
    await assertFails(deleteDoc(doc(db('bob'), `${base()}/wishlist/a1`)));
    await assertSucceeds(updateDoc(doc(db('alice'), `${base()}/wishlist/a1`), { received: true }));
  });
  it('cannot add a wish for someone else; links must be http(s)', async () => {
    await assertFails(setDoc(doc(db('alice'), `${base()}/wishlist/a2`), wish({ createdBy: 'bob' })));
    await assertFails(setDoc(doc(db('alice'), `${base()}/wishlist/a3`), wish({ url: 'javascript:alert(1)' })));
  });
});

describe('wishlist claims (secret)', () => {
  const claim = (o = {}) => ({ claimedBy: 'alice', itemOwner: 'bob', claimedAt: ts(), purchased: false, ...o });
  it("alice can claim bob's wish and see her claim", async () => {
    await assertSucceeds(setDoc(doc(db('alice'), `${base()}/wishlistClaims/w1`), claim()));
    await assertSucceeds(getDoc(doc(db('alice'), `${base()}/wishlistClaims/w1`)));
    await assertSucceeds(getDocs(query(collection(db('alice'), `${base()}/wishlistClaims`), where('claimedBy', '==', 'alice'))));
    await assertSucceeds(updateDoc(doc(db('alice'), `${base()}/wishlistClaims/w1`), { purchased: true }));
  });
  it('bob (the owner) can never see claims on his wishes', async () => {
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), `${base()}/wishlistClaims/w1`), claim()));
    await assertFails(getDoc(doc(db('bob'), `${base()}/wishlistClaims/w1`)));
    await assertFails(getDocs(collection(db('bob'), `${base()}/wishlistClaims`)));
    await assertFails(getDocs(query(collection(db('bob'), `${base()}/wishlistClaims`), where('itemOwner', '==', 'bob'))));
    await assertFails(deleteDoc(doc(db('bob'), `${base()}/wishlistClaims/w1`)));
  });
  it('cannot claim your own wish or fake the owner', async () => {
    await assertFails(setDoc(doc(db('bob'), `${base()}/wishlistClaims/w1`), claim({ claimedBy: 'bob', itemOwner: 'bob' })));
    await assertFails(setDoc(doc(db('alice'), `${base()}/wishlistClaims/w1`), claim({ itemOwner: 'alice' })));
    await assertFails(setDoc(doc(db('alice'), `${base()}/wishlistClaims/w1`), claim({ claimedBy: 'bob' })));
  });
  it('the claimer cannot reassign a claim', async () => {
    await assertSucceeds(setDoc(doc(db('alice'), `${base()}/wishlistClaims/w1`), claim()));
    await assertFails(updateDoc(doc(db('alice'), `${base()}/wishlistClaims/w1`), { claimedBy: 'bob' }));
    await assertSucceeds(deleteDoc(doc(db('alice'), `${base()}/wishlistClaims/w1`)));
  });
});

describe('places', () => {
  const place = (o = {}) => ({
    name: 'Toit', area: 'Indiranagar', mapsUrl: '', category: 'bar', status: 'wantToGo',
    rating: null, visitedAt: null, notes: '', favourite: false, createdBy: 'bob', ...o,
  });
  it('members add and mark as been', async () => {
    await assertSucceeds(setDoc(doc(db('bob'), `${base()}/places/p1`), place()));
    await assertSucceeds(updateDoc(doc(db('alice'), `${base()}/places/p1`), { status: 'been', rating: 5, visitedAt: ts() }));
  });
  it('rejects unknown status and bad maps links', async () => {
    await assertFails(setDoc(doc(db('bob'), `${base()}/places/p2`), place({ status: 'maybe' })));
    await assertFails(setDoc(doc(db('bob'), `${base()}/places/p3`), place({ mapsUrl: 'ftp://x' })));
  });
});

describe('expenses', () => {
  const exp = (o = {}) => ({
    kind: 'expense', title: 'Dinner', amountMinor: 250000, paidBy: 'alice', split: 'equal',
    shares: null, category: 'food', spentOn: ts(), note: '', createdBy: 'alice', ...o,
  });
  it('members add; either edits; only the creator deletes', async () => {
    await assertSucceeds(setDoc(doc(db('alice'), `${base()}/expenses/e1`), exp()));
    await assertSucceeds(updateDoc(doc(db('bob'), `${base()}/expenses/e1`), { amountMinor: 260000 }));
    await assertFails(deleteDoc(doc(db('bob'), `${base()}/expenses/e1`)));
    await assertSucceeds(deleteDoc(doc(db('alice'), `${base()}/expenses/e1`)));
  });
  it('custom splits and settlements', async () => {
    await assertSucceeds(setDoc(doc(db('bob'), `${base()}/expenses/e2`), exp({ split: 'custom', shares: { alice: 100000, bob: 150000 }, createdBy: 'bob' })));
    await assertSucceeds(setDoc(doc(db('bob'), `${base()}/expenses/s1`), exp({ kind: 'settlement', title: 'Settle up', split: 'full', paidBy: 'bob', category: 'other', createdBy: 'bob' })));
    await assertFails(setDoc(doc(db('bob'), `${base()}/expenses/s2`), exp({ kind: 'settlement', split: 'equal', createdBy: 'bob' })));
  });
  it('rejects floats, zero, non-members and missing shares', async () => {
    const r = (o) => setDoc(doc(db('alice'), `${base()}/expenses/x`), exp(o));
    await assertFails(r({ amountMinor: 12.5 }));
    await assertFails(r({ amountMinor: 0 }));
    await assertFails(r({ paidBy: 'eve' }));
    await assertFails(r({ split: 'custom', shares: null }));
    await assertFails(r({ category: 'crypto' }));
  });
  it('strangers cannot read the ledger', async () => {
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), `${base()}/expenses/e1`), exp()));
    await assertFails(getDoc(doc(db('eve'), `${base()}/expenses/e1`)));
  });
});

});
