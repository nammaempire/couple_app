// Rules for couples/{id}/settings/chatLook and the chat-look fields on profiles.
const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment, assertSucceeds, assertFails,
} = require('@firebase/rules-unit-testing');
const { doc, getDoc, setDoc, deleteDoc, serverTimestamp } = require('firebase/firestore');

const C = 'couple1';
let env;
const db = (uid) => env.authenticatedContext(uid).firestore();
const look = (uid, o = {}) => doc(db(uid), `couples/${C}/settings/${o.id || 'chatLook'}`);
const data = (o = {}) => ({
  color: 0xff3f6ad8,
  background: { kind: 'pattern', patternId: 'hearts', photoUrl: null, storagePath: null, dim: 0.25, blur: 0 },
  updatedBy: 'alice', updatedAt: serverTimestamp(), ...o,
});

describe('chat look rules', () => {
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
      await setDoc(doc(ctx.firestore(), 'users/alice'), { displayName: 'Alice', coupleId: C });
    });
  });

  it('either partner sets the shared look; both read it', async () => {
    await assertSucceeds(setDoc(look('alice'), data()));
    await assertSucceeds(getDoc(look('bob')));
    await assertSucceeds(setDoc(look('bob'), data({ color: null, updatedBy: 'bob',
      background: { kind: 'photo', photoUrl: 'https://firebasestorage.googleapis.com/x', storagePath: `couples/${C}/backgrounds/a.jpg`, dim: 0.4, blur: 6 } })));
  });
  it('strangers cannot read or write it', async () => {
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), `couples/${C}/settings/chatLook`), data()));
    await assertFails(getDoc(look('eve')));
    await assertFails(setDoc(look('eve'), data({ updatedBy: 'eve' })));
  });
  it('rejects bad values', async () => {
    const bg = (o) => ({ kind: 'photo', photoUrl: 'https://x.y/z', dim: 0.2, blur: 2, ...o });
    await assertFails(setDoc(look('alice'), data({ updatedBy: 'bob' })));
    await assertFails(setDoc(look('alice'), data({ color: 'red' })));
    await assertFails(setDoc(look('alice'), data({ background: bg({ kind: 'video' }) })));
    await assertFails(setDoc(look('alice'), data({ background: bg({ dim: 0.95 }) })));
    await assertFails(setDoc(look('alice'), data({ background: bg({ blur: 40 }) })));
    await assertFails(setDoc(look('alice'), data({ background: bg({ photoUrl: 'http://insecure/x' }) })));
    await assertFails(setDoc(look('alice', { id: 'other' }), data()));
  });
  it('nobody deletes it', async () => {
    await assertSucceeds(setDoc(look('alice'), data()));
    await assertFails(deleteDoc(look('alice')));
  });
  it('a person saves their own personal look on their profile', async () => {
    await assertSucceeds(setDoc(doc(db('alice'), 'users/alice'),
      { chatLookMode: 'personal', chatLook: { color: 1, background: { kind: 'none' } } }, { merge: true }));
    await assertFails(setDoc(doc(db('bob'), 'users/alice'), { chatLookMode: 'shared' }, { merge: true }));
  });
});
