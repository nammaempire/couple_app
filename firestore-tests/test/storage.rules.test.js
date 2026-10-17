// Storage rules for chat backgrounds (shared and personal).
const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment, assertSucceeds, assertFails,
} = require('@firebase/rules-unit-testing');
const { doc, setDoc } = require('firebase/firestore');
const { ref, uploadBytes, getBytes, deleteObject } = require('firebase/storage');

const C = 'couple1';
let env;
const st = (uid) => env.authenticatedContext(uid).storage();
const jpg = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);
const put = (uid, p, type = 'image/jpeg', bytes = jpg) =>
  uploadBytes(ref(st(uid), p), bytes, { contentType: type });

describe('storage rules', () => {
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
    await env.clearFirestore();
    await env.clearStorage();
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `couples/${C}`), { memberIds: ['alice', 'bob'], inviteCode: 'ABC234' });
      await setDoc(doc(ctx.firestore(), 'users/alice'), { coupleId: C });
      await setDoc(doc(ctx.firestore(), 'users/bob'), { coupleId: C });
    });
  });

  it('shared backgrounds: both partners read, strangers cannot', async () => {
    await assertSucceeds(put('alice', `couples/${C}/backgrounds/a.jpg`));
    await assertSucceeds(getBytes(ref(st('bob'), `couples/${C}/backgrounds/a.jpg`)));
    await assertFails(getBytes(ref(st('eve'), `couples/${C}/backgrounds/a.jpg`)));
    await assertFails(put('eve', `couples/${C}/backgrounds/b.jpg`));
  });
  it('shared backgrounds must be images under 10 MB', async () => {
    await assertFails(put('alice', `couples/${C}/backgrounds/a.mp4`, 'video/mp4'));
    await assertFails(put('alice', `couples/${C}/backgrounds/big.jpg`, 'image/jpeg', new Uint8Array(11 * 1024 * 1024)));
  });
  it('personal backgrounds are private to their owner', async () => {
    await assertSucceeds(put('alice', 'users/alice/backgrounds/a.jpg'));
    await assertSucceeds(getBytes(ref(st('alice'), 'users/alice/backgrounds/a.jpg')));
    await assertFails(getBytes(ref(st('bob'), 'users/alice/backgrounds/a.jpg')));
    await assertFails(put('bob', 'users/alice/backgrounds/x.jpg'));
    await assertFails(deleteObject(ref(st('bob'), 'users/alice/backgrounds/a.jpg')));
    await assertSucceeds(deleteObject(ref(st('alice'), 'users/alice/backgrounds/a.jpg')));
  });
});
