// Rules for avatar fields on profiles and couple sticker messages.
const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment, assertSucceeds, assertFails,
} = require('@firebase/rules-unit-testing');
const { doc, getDoc, setDoc, addDoc, updateDoc, collection, serverTimestamp } = require('firebase/firestore');

const C = 'couple1';
let env;
const db = (uid) => env.authenticatedContext(uid).firestore();
const avatar = { skin: 'skin4', face: 'oval', hair: 'long', hairColor: 'black', eyes: 'round', eyeColor: 'brown', brows: 'soft', facialHair: 'none', glasses: 'none', accessory: 'earrings', faceAccessory: 'bindi', outfit: 'saree', outfitColor: 'rose', background: 'blush' };
const sticker = (o = {}) => ({
  senderId: 'alice', type: 'sticker', text: 'Same moon, different windows.',
  sticker: { id: 'miss-moon', category: 'missYou' }, sentAt: serverTimestamp(),
  seen: false, reactions: {}, imageUrl: null, imageAspectRatio: null, ...o,
});

describe('avatar and sticker rules', () => {
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
      await setDoc(doc(ctx.firestore(), 'users/bob'), { displayName: 'Bob', coupleId: C });
    });
  });

  it('saves my avatar (merge) and my partner can see it', async () => {
    await assertSucceeds(setDoc(doc(db('alice'), 'users/alice'), { avatar, avatarAsPhoto: true }, { merge: true }));
    await assertSucceeds(getDoc(doc(db('bob'), 'users/alice')));
  });
  it('a first-time profile can include an avatar', async () => {
    await assertSucceeds(setDoc(doc(db('carol'), 'users/carol'), { displayName: 'Carol', avatar }));
  });
  it('rejects malformed avatar fields', async () => {
    const big = Object.fromEntries(Array.from({ length: 30 }, (_, i) => [`k${i}`, 'x']));
    await assertFails(setDoc(doc(db('alice'), 'users/alice'), { avatar: 'not a map' }, { merge: true }));
    await assertFails(setDoc(doc(db('alice'), 'users/alice'), { avatar: big }, { merge: true }));
    await assertFails(setDoc(doc(db('alice'), 'users/alice'), { avatarAsPhoto: 'yes' }, { merge: true }));
  });
  it('nobody else edits my avatar', async () => {
    await assertFails(setDoc(doc(db('bob'), 'users/alice'), { avatar }, { merge: true }));
  });
  it('sends a sticker; partner can react but not change it', async () => {
    const ref = await assertSucceeds(addDoc(collection(db('alice'), `couples/${C}/messages`), sticker()));
    await assertSucceeds(updateDoc(doc(db('bob'), `couples/${C}/messages/${ref.id}`), { reactions: { bob: '❤️' } }));
    await assertFails(updateDoc(doc(db('bob'), `couples/${C}/messages/${ref.id}`), { text: 'changed' }));
  });
  it('rejects malformed stickers', async () => {
    const send = (o) => addDoc(collection(db('alice'), `couples/${C}/messages`), sticker(o));
    await assertFails(send({ sticker: 'junk' }));
    await assertFails(send({ sticker: { id: '' } }));
    await assertFails(send({ text: 'x'.repeat(401) }));
    await assertFails(send({ senderId: 'bob' }));
  });
  it('ordinary messages are unaffected', async () => {
    await assertSucceeds(addDoc(collection(db('alice'), `couples/${C}/messages`), { senderId: 'alice', type: 'text', text: 'hi', sentAt: serverTimestamp() }));
  });
});
