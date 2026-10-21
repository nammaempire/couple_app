// Rules for "Clear chat for both", system messages and the shared
// screenshot-blocking switch.
const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment, assertSucceeds, assertFails,
} = require('@firebase/rules-unit-testing');
const {
  doc, getDoc, setDoc, addDoc, updateDoc, deleteDoc, collection,
  serverTimestamp, Timestamp, writeBatch,
} = require('firebase/firestore');

const C = 'couple1';
let env;
const dbs = {};
const db = (uid) => (dbs[uid] ||= env.authenticatedContext(uid).firestore());
const couple = (uid) => doc(db(uid), `couples/${C}`);
const msg = (uid, id) => doc(db(uid), `couples/${C}/messages/${id}`);

describe('chat privacy rules', () => {
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
    await env.withSecurityRulesDisabled(async (ctx) => {
      const f = ctx.firestore();
      await setDoc(doc(f, `couples/${C}`), { memberIds: ['alice', 'bob'], inviteCode: 'ABC234' });
      const old = Timestamp.fromMillis(Date.now() - 60000);
      await setDoc(doc(f, `couples/${C}/messages/a1`), { senderId: 'alice', type: 'text', text: 'hi', sentAt: old });
      await setDoc(doc(f, `couples/${C}/messages/b1`), { senderId: 'bob', type: 'text', text: 'hey', sentAt: old });
      await setDoc(doc(f, `couples/${C}/messages/b2`), { senderId: 'bob', type: 'text', text: 'later',
        sentAt: Timestamp.fromMillis(Date.now() + 3600000) });
    });
  });

  it("without a clear, you can't delete your partner's messages", async () => {
    await assertFails(deleteDoc(msg('alice', 'b1')));
    await assertSucceeds(deleteDoc(msg('alice', 'a1')));
  });

  it('clear for both: stamp server time, then either deletes up to it', async () => {
    await assertSucceeds(updateDoc(couple('alice'), { chatClearedAt: serverTimestamp(), chatClearedBy: 'alice' }));
    await assertSucceeds(deleteDoc(msg('alice', 'b1')));
    await assertSucceeds(deleteDoc(msg('alice', 'a1')));
    // A message sent after the clear is still protected.
    await assertFails(deleteDoc(msg('alice', 'b2')));
  });

  it('the clear stamp must be server time and your own uid', async () => {
    await assertFails(updateDoc(couple('alice'), { chatClearedAt: Timestamp.fromMillis(Date.now() + 86400000) }));
    await assertFails(updateDoc(couple('alice'), { chatClearedAt: serverTimestamp(), chatClearedBy: 'bob' }));
    await assertFails(updateDoc(doc(db('carol'), `couples/${C}`), { chatClearedAt: serverTimestamp() }));
  });

  it('system messages: sent as yourself; partner cannot delete them', async () => {
    const ref = await assertSucceeds(addDoc(collection(db('alice'), `couples/${C}/messages`),
      { senderId: 'alice', type: 'screenshot', text: '📸 Alice took a screenshot', sentAt: serverTimestamp() }));
    await assertFails(addDoc(collection(db('alice'), `couples/${C}/messages`),
      { senderId: 'bob', type: 'screenshot', text: 'fake', sentAt: serverTimestamp() }));
    await assertFails(deleteDoc(msg('bob', ref.id)));
    await assertFails(updateDoc(msg('bob', ref.id), { text: 'edited' }));
  });

  it('system messages are short text only and cannot be reacted to or pinned', async () => {
    const send = (o) => addDoc(collection(db('alice'), `couples/${C}/messages`),
      { senderId: 'alice', type: 'chatCleared', text: 'Alice cleared the chat', sentAt: serverTimestamp(), seen: true, ...o });
    await assertFails(send({ text: 'x'.repeat(201) }));
    await assertFails(send({ imageUrl: 'https://x/y.jpg' }));
    await assertFails(send({ reactions: { bob: '❤️' } }));
    const ref = await assertSucceeds(send({}));
    await assertFails(updateDoc(msg('bob', ref.id), { reactions: { bob: '❤️' } }));
    await assertFails(updateDoc(msg('bob', ref.id), { pinned: true }));
    await assertSucceeds(updateDoc(msg('bob', ref.id), { seen: true }));
  });

  it('clear for both deletes 400 messages in one batch', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const f = ctx.firestore();
      let b = writeBatch(f);
      const old = Timestamp.fromMillis(Date.now() - 60000);
      for (let i = 0; i < 400; i++) {
        b.set(doc(f, `couples/${C}/messages/m${i}`), { senderId: i % 2 ? 'bob' : 'alice', type: 'text', text: `${i}`, sentAt: old });
      }
      await b.commit();
    });
    await assertSucceeds(updateDoc(couple('alice'), { chatClearedAt: serverTimestamp(), chatClearedBy: 'alice' }));
    const batch = writeBatch(db('alice'));
    for (let i = 0; i < 400; i++) batch.delete(msg('alice', `m${i}`));
    await assertSucceeds(batch.commit());
  });

  it('either partner flips the shared screenshot switch; it must be a bool', async () => {
    await assertSucceeds(updateDoc(couple('bob'), { blockScreenshots: true }));
    await assertSucceeds(updateDoc(couple('alice'), { blockScreenshots: false }));
    await assertFails(updateDoc(couple('alice'), { blockScreenshots: 'yes' }));
    await assertFails(updateDoc(doc(db('carol'), `couples/${C}`), { blockScreenshots: true }));
  });

  it('clear for me is just your own profile field', async () => {
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'users/alice'), { displayName: 'Alice', coupleId: C }));
    await assertSucceeds(updateDoc(doc(db('alice'), 'users/alice'), { chatClearedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(db('bob'), 'users/alice'), { chatClearedAt: serverTimestamp() }));
  });
});
