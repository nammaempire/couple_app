// Reproduces the exact writes the Dart services make (including server
// timestamps, merges and null fields), so a rules change can't silently
// break the app.
const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment, assertSucceeds, assertFails,
} = require('@firebase/rules-unit-testing');
const {
  doc, getDoc, setDoc, updateDoc, deleteDoc, addDoc, collection, query, where,
  getDocs, Timestamp, serverTimestamp,
} = require('firebase/firestore');

const C = 'couple1';
let env;
const T = () => Timestamp.fromDate(new Date('2026-10-18T14:00:00Z'));
const db = (uid) => env.authenticatedContext(uid).firestore();
const col = (uid, name) => collection(db(uid), `couples/${C}/${name}`);
const d = (uid, name, id) => doc(db(uid), `couples/${C}/${name}/${id}`);
const merge = { merge: true };


// scoped-hooks: keep this file's before/beforeEach from running for other files.
describe('app-writes rules', () => {
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
    await setDoc(doc(ctx.firestore(), `couples/${C}`), { memberIds: ['alice', 'bob'], inviteCode: 'ABC234' });
  });
});

describe('exact: date plans', () => {
  // DatePlan.toMap() for a new idea + createdAt only (no updatedAt).
  const idea = {
    title: 'Sunset picnic', notes: '', status: 'idea', scheduledAt: null, location: '',
    estimatedCostMinor: null, vibe: 'cozy', rating: null, reflection: '',
    createdBy: 'alice', completedAt: null,
  };
  it('add idea / place->date idea', async () => {
    await assertSucceeds(addDoc(col('alice', 'datePlans'), { ...idea, createdAt: serverTimestamp() }));
    await assertSucceeds(addDoc(col('bob', 'datePlans'), { ...idea, title: 'Date at Toit', location: 'Toit, Indiranagar', vibe: 'fancy', createdBy: 'bob', createdAt: serverTimestamp() }));
  });
  it('add planned via editor', async () => {
    await assertSucceeds(addDoc(col('alice', 'datePlans'), { ...idea, status: 'planned', scheduledAt: T(), estimatedCostMinor: 0, createdAt: serverTimestamp() }));
  });
  it('schedule / markDone / moveToIdeas / edit by partner / delete', async () => {
    await assertSucceeds(setDoc(d('alice', 'datePlans', 'p1'), { ...idea, createdAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(d('bob', 'datePlans', 'p1'), { status: 'planned', scheduledAt: T(), completedAt: null, updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(d('bob', 'datePlans', 'p1'), { status: 'done', rating: null, reflection: '', completedAt: serverTimestamp(), updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(d('alice', 'datePlans', 'p1'), { status: 'done', rating: 5, reflection: 'Lovely', completedAt: serverTimestamp(), updatedAt: serverTimestamp() }));
    await assertSucceeds(setDoc(d('bob', 'datePlans', 'p1'), { ...idea, status: 'done', scheduledAt: T(), rating: 4, reflection: 'x', completedAt: T(), updatedAt: serverTimestamp() }, merge));
    await assertSucceeds(updateDoc(d('alice', 'datePlans', 'p1'), { status: 'idea', scheduledAt: null, rating: null, completedAt: null, updatedAt: serverTimestamp() }));
    await assertSucceeds(deleteDoc(d('bob', 'datePlans', 'p1')));
  });
  it('overflowed cost (DatePlanCost.parseMinor of 17 digits) is denied', async () => {
    await assertFails(addDoc(col('alice', 'datePlans'), { ...idea, estimatedCostMinor: -8446744073709551716, createdAt: serverTimestamp() }));
  });
});

describe('exact: bucket list', () => {
  const item = { title: 'Salsa', notes: '', category: 'learn', done: false, doneAt: null, doneBy: null, targetYear: null, createdBy: 'alice' };
  it('add, edit merge by partner, setDone on/off', async () => {
    const ref = await assertSucceeds(addDoc(col('alice', 'bucketList'), { ...item, createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
    const id = ref.id;
    await assertSucceeds(setDoc(d('bob', 'bucketList', id), { title: 'Salsa!', notes: 'n', category: 'romance', targetYear: 2027, updatedAt: serverTimestamp() }, merge));
    await assertSucceeds(updateDoc(d('bob', 'bucketList', id), { done: true, doneAt: serverTimestamp(), doneBy: 'bob', updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(d('alice', 'bucketList', id), { done: false, doneAt: null, doneBy: null, updatedAt: serverTimestamp() }));
    await assertSucceeds(deleteDoc(d('bob', 'bucketList', id)));
  });
});

describe('exact: wishlist + claims', () => {
  const wish = { title: 'Kindle', notes: '', url: '', priceMinor: null, priority: 'like', occasion: 'any', createdBy: 'bob', received: false };
  it('add / edit merge / received / delete', async () => {
    const ref = await assertSucceeds(addDoc(col('bob', 'wishlist'), { ...wish, createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
    await assertSucceeds(setDoc(d('bob', 'wishlist', ref.id), { title: 'Kindle', notes: '', url: 'https://amazon.in/x', priceMinor: 1299900, priority: 'love', occasion: 'birthday', updatedAt: serverTimestamp() }, merge));
    await assertSucceeds(updateDoc(d('bob', 'wishlist', ref.id), { received: true, updatedAt: serverTimestamp() }));
    await assertSucceeds(deleteDoc(d('bob', 'wishlist', ref.id)));
  });
  it('links with an uppercase scheme are accepted, like the app does', async () => {
    await assertSucceeds(addDoc(col('bob', 'wishlist'), { ...wish, url: 'HTTPS://amazon.in/x', createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
    await assertSucceeds(addDoc(col('bob', 'wishlist'), { ...wish, url: 'Https://amazon.in/x', createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
    await assertFails(addDoc(col('bob', 'wishlist'), { ...wish, url: 'javascript:alert(1)', createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
  });
  it('claim (set, serverTimestamp), list, purchased, unclaim', async () => {
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), `couples/${C}/wishlist/w1`), wish));
    await assertSucceeds(setDoc(d('alice', 'wishlistClaims', 'w1'), { claimedBy: 'alice', itemOwner: 'bob', purchased: false, claimedAt: serverTimestamp() }));
    await assertSucceeds(getDocs(query(col('alice', 'wishlistClaims'), where('claimedBy', '==', 'alice'))));
    await assertSucceeds(updateDoc(d('alice', 'wishlistClaims', 'w1'), { purchased: true }));
    await assertSucceeds(updateDoc(d('alice', 'wishlistClaims', 'w1'), { purchased: false }));
    await assertSucceeds(deleteDoc(d('alice', 'wishlistClaims', 'w1')));
  });
  // The app catches this and treats an existing claim of mine as done.
  it('claiming again while a claim exists (retry / second device) is denied', async () => {
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), `couples/${C}/wishlist/w1`), wish));
    await assertSucceeds(setDoc(d('alice', 'wishlistClaims', 'w1'), { claimedBy: 'alice', itemOwner: 'bob', purchased: false, claimedAt: serverTimestamp() }));
    await assertFails(setDoc(d('alice', 'wishlistClaims', 'w1'), { claimedBy: 'alice', itemOwner: 'bob', purchased: false, claimedAt: serverTimestamp() }));
  });
  it('owner probing: get/delete/create on missing and existing claim all denied', async () => {
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), `couples/${C}/wishlist/w1`), wish));
    await assertFails(getDoc(d('bob', 'wishlistClaims', 'w1')));
    await assertFails(deleteDoc(d('bob', 'wishlistClaims', 'w1')));
    await assertFails(setDoc(d('bob', 'wishlistClaims', 'w1'), { claimedBy: 'bob', itemOwner: 'bob', purchased: false, claimedAt: serverTimestamp() }));
    await assertSucceeds(setDoc(d('alice', 'wishlistClaims', 'w1'), { claimedBy: 'alice', itemOwner: 'bob', purchased: false, claimedAt: serverTimestamp() }));
    await assertFails(getDoc(d('bob', 'wishlistClaims', 'w1')));
    await assertFails(deleteDoc(d('bob', 'wishlistClaims', 'w1')));
    await assertFails(setDoc(d('bob', 'wishlistClaims', 'w1'), { claimedBy: 'bob', itemOwner: 'bob', purchased: false, claimedAt: serverTimestamp() }));
    await assertFails(updateDoc(d('bob', 'wishlistClaims', 'w1'), { purchased: true }));
  });
  it('owner can delete wish; orphan claim survives (claimer still lists it)', async () => {
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), `couples/${C}/wishlist/w1`), wish));
    await assertSucceeds(setDoc(d('alice', 'wishlistClaims', 'w1'), { claimedBy: 'alice', itemOwner: 'bob', purchased: false, claimedAt: serverTimestamp() }));
    await assertSucceeds(deleteDoc(d('bob', 'wishlist', 'w1')));
    const snap = await getDocs(query(col('alice', 'wishlistClaims'), where('claimedBy', '==', 'alice')));
    if (snap.size !== 1) throw new Error('expected orphan');
  });
});

describe('exact: places', () => {
  const place = { name: 'Toit', area: 'Indiranagar', mapsUrl: '', category: 'bar', status: 'wantToGo', rating: null, visitedAt: null, notes: '', favourite: false, createdBy: 'bob' };
  it('add / merge edit / favourite / markBeen / markWantToGo / delete', async () => {
    const ref = await assertSucceeds(addDoc(col('bob', 'places'), { ...place, createdAt: serverTimestamp() }));
    const id = ref.id;
    await assertSucceeds(setDoc(d('alice', 'places', id), { ...place, mapsUrl: 'https://maps.app.goo.gl/abc', updatedAt: serverTimestamp() }, merge));
    await assertSucceeds(updateDoc(d('alice', 'places', id), { favourite: true, updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(d('alice', 'places', id), { status: 'been', visitedAt: T(), rating: null, notes: '', updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(d('alice', 'places', id), { status: 'wantToGo', visitedAt: null, rating: null, updatedAt: serverTimestamp() }));
    await assertSucceeds(deleteDoc(d('alice', 'places', id)));
  });
  it('maps links with an uppercase scheme are accepted', async () => {
    await assertSucceeds(addDoc(col('bob', 'places'), { ...place, mapsUrl: 'HTTPS://maps.google.com/x', createdAt: serverTimestamp() }));
  });
});

describe('exact: expenses + currency', () => {
  const base = { kind: 'expense', title: 'Dinner', amountMinor: 125050, paidBy: 'alice', split: 'equal', shares: null, category: 'food', spentOn: T(), note: '', createdBy: 'alice' };
  it('add equal/full/custom, partner edits via merge, settle, delete', async () => {
    const r1 = await assertSucceeds(addDoc(col('alice', 'expenses'), { ...base, createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
    await assertSucceeds(addDoc(col('alice', 'expenses'), { ...base, split: 'full', paidBy: 'bob', createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
    await assertSucceeds(addDoc(col('alice', 'expenses'), { ...base, split: 'custom', shares: { alice: 25050, bob: 100000 }, createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
    await assertSucceeds(setDoc(d('bob', 'expenses', r1.id), { ...base, split: 'custom', shares: { alice: 0, bob: 125050 }, updatedAt: serverTimestamp() }, merge));
    await assertSucceeds(setDoc(d('bob', 'expenses', r1.id), { ...base, split: 'equal', shares: null, updatedAt: serverTimestamp() }, merge));
    await assertSucceeds(addDoc(col('bob', 'expenses'), { ...base, kind: 'settlement', title: 'Settle up', split: 'full', paidBy: 'alice', category: 'other', createdBy: 'bob', createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
    await assertSucceeds(addDoc(col('alice', 'expenses'), { ...base, amountMinor: 1000000000, createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
    await assertFails(deleteDoc(d('bob', 'expenses', r1.id)));
    await assertSucceeds(deleteDoc(d('alice', 'expenses', r1.id)));
  });
  it('custom shares summing wrong are accepted by rules (no server check)', async () => {
    await assertSucceeds(addDoc(col('alice', 'expenses'), { ...base, split: 'custom', shares: { alice: 1, bob: 1 }, createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
  });
  it('setCurrency merge', async () => {
    await assertSucceeds(setDoc(doc(db('bob'), `couples/${C}`), { currency: 'USD' }, merge));
  });
});

});
