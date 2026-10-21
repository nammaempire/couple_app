// Rules for saved songs and the shared "listening together" session, using
// the same writes the app makes (see lib/features/music/data/music_service.dart).
const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment, assertSucceeds, assertFails,
} = require('@firebase/rules-unit-testing');
const {
  doc, getDoc, setDoc, addDoc, updateDoc, deleteDoc, collection,
  serverTimestamp, increment, deleteField, runTransaction,
} = require('firebase/firestore');

const C = 'couple1';
let env;
const db = (uid) => env.authenticatedContext(uid).firestore();

const song = (o = {}) => ({
  url: 'https://www.youtube.com/watch?v=BddP6PYo2gs', source: 'youtube',
  kind: 'video', mediaId: 'BddP6PYo2gs', title: 'Tum Hi Ho',
  artist: 'Arijit Singh', thumbnailUrl: 'https://i.ytimg.com/vi/BddP6PYo2gs/hqdefault.jpg',
  note: 'Our first dance', moment: 'ourSong', addedBy: 'alice',
  lovedBy: { alice: true }, playCount: 0, createdAt: serverTimestamp(), ...o,
});

const session = (o = {}) => ({
  songId: 's1', url: 'https://www.youtube.com/watch?v=BddP6PYo2gs',
  source: 'youtube', mediaId: 'BddP6PYo2gs', title: 'Tum Hi Ho',
  artist: 'Arijit Singh', thumbnailUrl: '', status: 'countdown',
  positionMs: 0, at: 1760000004000, queue: ['s2'], hostUid: 'alice',
  updatedBy: 'alice', listeners: { alice: 1760000000000 }, version: 1,
  updatedAt: serverTimestamp(), ...o,
});

describe('music rules', () => {
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
      const f = ctx.firestore();
      await setDoc(doc(f, `couples/${C}`), { memberIds: ['alice', 'bob'], inviteCode: 'ABC234' });
      await setDoc(doc(f, 'couples/other'), { memberIds: ['carol'], inviteCode: 'XYZ234' });
      await setDoc(doc(f, `couples/${C}/songs/s1`), song({ createdAt: new Date() }));
    });
  });

  describe('songs', () => {
    it('either partner adds a song; both can read it', async () => {
      await assertSucceeds(addDoc(collection(db('bob'), `couples/${C}/songs`), song({ addedBy: 'bob', lovedBy: { bob: true } })));
      await assertSucceeds(getDoc(doc(db('alice'), `couples/${C}/songs/s1`)));
    });

    it('strangers cannot read or add songs', async () => {
      await assertFails(getDoc(doc(db('carol'), `couples/${C}/songs/s1`)));
      await assertFails(addDoc(collection(db('carol'), `couples/${C}/songs`), song({ addedBy: 'carol', lovedBy: {} })));
    });

    it('rejects bad songs', async () => {
      const add = (o) => addDoc(collection(db('alice'), `couples/${C}/songs`), song(o));
      await assertFails(add({ addedBy: 'bob' }));
      await assertFails(add({ url: 'http://insecure.example/x' }));
      await assertFails(add({ url: 'javascript:alert(1)' }));
      await assertFails(add({ source: 'napster' }));
      await assertFails(add({ moment: 'angry' }));
      await assertFails(add({ note: 'x'.repeat(501) }));
      await assertFails(add({ title: 'x'.repeat(201) }));
      await assertFails(add({ playCount: 5 }));
      await assertFails(add({ lovedBy: { carol: true } }));
      await assertSucceeds(add({ thumbnailUrl: '' }));
    });

    it('edits details, love and plays, but never the link or who added it', async () => {
      const ref = doc(db('bob'), `couples/${C}/songs/s1`);
      await assertSucceeds(updateDoc(ref, { title: 'Tum Hi Ho (Aashiqui 2)', note: 'Still ours', moment: 'romantic', updatedAt: serverTimestamp() }));
      await assertSucceeds(updateDoc(ref, { 'lovedBy.bob': true }));
      await assertSucceeds(updateDoc(ref, { 'lovedBy.alice': deleteField() }));
      await assertSucceeds(updateDoc(ref, { playCount: increment(1), lastPlayedAt: serverTimestamp() }));
      await assertFails(updateDoc(ref, { playCount: 50 }));
      await assertFails(updateDoc(ref, { url: 'https://youtu.be/AAAAAAAAAAA' }));
      await assertFails(updateDoc(ref, { mediaId: 'AAAAAAAAAAA' }));
      await assertFails(updateDoc(ref, { addedBy: 'bob' }));
      await assertFails(updateDoc(ref, { 'lovedBy.carol': true }));
    });

    it('either partner deletes; strangers cannot', async () => {
      await assertFails(deleteDoc(doc(db('carol'), `couples/${C}/songs/s1`)));
      await assertSucceeds(deleteDoc(doc(db('bob'), `couples/${C}/songs/s1`)));
    });
  });

  describe('listening together', () => {
    const now = (uid) => doc(db(uid), `couples/${C}/listening/now`);

    it('starts a session, then each change bumps the version by one', async () => {
      await assertSucceeds(setDoc(now('alice'), session()));
      await assertSucceeds(getDoc(now('bob')));
      // Bob pauses (version 2), Alice resumes (version 3).
      await assertSucceeds(updateDoc(now('bob'), { status: 'paused', positionMs: 30000, at: 1760000034000, updatedBy: 'bob', version: 2, updatedAt: serverTimestamp() }));
      await assertSucceeds(updateDoc(now('alice'), { status: 'playing', at: 1760000040000, updatedBy: 'alice', version: 3, updatedAt: serverTimestamp() }));
    });

    it('rejects stale or skipped versions and impersonation', async () => {
      await assertSucceeds(setDoc(now('alice'), session()));
      await assertFails(updateDoc(now('bob'), { status: 'paused', updatedBy: 'bob', version: 1, updatedAt: serverTimestamp() }));
      await assertFails(updateDoc(now('bob'), { status: 'paused', updatedBy: 'bob', version: 5, updatedAt: serverTimestamp() }));
      await assertFails(updateDoc(now('bob'), { status: 'paused', updatedBy: 'alice', version: 2, updatedAt: serverTimestamp() }));
      await assertFails(updateDoc(now('bob'), { status: 'paused', updatedBy: 'bob', version: 2 }));
    });

    it('a fresh start replaces an ended session through a transaction', async () => {
      await env.withSecurityRulesDisabled((ctx) => setDoc(
        doc(ctx.firestore(), `couples/${C}/listening/now`),
        session({ status: 'ended', version: 7, updatedAt: new Date() })));
      const bob = db('bob');
      const ref = doc(bob, `couples/${C}/listening/now`);
      await assertSucceeds(runTransaction(bob, async (tx) => {
        const snap = await tx.get(ref);
        tx.set(ref, session({ songId: 's2', hostUid: 'bob', updatedBy: 'bob', listeners: { bob: 1 }, version: snap.data().version + 1 }));
      }));
    });

    it('checking in touches only your own listener entry', async () => {
      await assertSucceeds(setDoc(now('alice'), session()));
      await assertSucceeds(updateDoc(now('bob'), { 'listeners.bob': 1760000001000 }));
      await assertSucceeds(updateDoc(now('bob'), { 'listeners.bob': deleteField() }));
      await assertFails(updateDoc(now('bob'), { 'listeners.alice': deleteField() }));
      await assertFails(updateDoc(now('bob'), { 'listeners.bob': 1, status: 'paused' }));
    });

    it('rejects malformed sessions', async () => {
      await assertFails(setDoc(now('alice'), session({ url: 'http://x.y' })));
      await assertFails(setDoc(now('alice'), session({ status: 'rewinding' })));
      await assertFails(setDoc(now('alice'), session({ positionMs: -5 })));
      await assertFails(setDoc(now('alice'), session({ hostUid: 'carol' })));
      await assertFails(setDoc(now('alice'), session({ listeners: { carol: 1 } })));
      await assertFails(setDoc(now('alice'), session({ queue: Array.from({ length: 51 }, (_, i) => `s${i}`) })));
      await assertFails(setDoc(now('alice'), session({ songId: '' })));
    });

    it('strangers cannot read or control it; nobody deletes it', async () => {
      await assertSucceeds(setDoc(now('alice'), session()));
      await assertFails(getDoc(now('carol')));
      await assertFails(updateDoc(now('carol'), { status: 'paused', updatedBy: 'carol', version: 2, updatedAt: serverTimestamp() }));
      await assertFails(deleteDoc(now('alice')));
    });

    it('clock docs: your own, server time only', async () => {
      const mine = doc(db('alice'), `couples/${C}/listening/clock-alice`);
      await assertSucceeds(setDoc(mine, { t: serverTimestamp() }));
      await assertSucceeds(getDoc(mine));
      await assertFails(getDoc(doc(db('bob'), `couples/${C}/listening/clock-alice`)));
      await assertFails(setDoc(doc(db('bob'), `couples/${C}/listening/clock-alice`), { t: serverTimestamp() }));
      await assertFails(setDoc(mine, { t: new Date(0) }));
      await assertFails(setDoc(mine, { t: serverTimestamp(), extra: 1 }));
      await assertFails(setDoc(doc(db('alice'), `couples/${C}/listening/other`), { t: serverTimestamp() }));
    });
  });

  describe('watch together', () => {
    const video = (o = {}) => song({ moment: 'movieNight', ...o });
    const watching = (uid) => doc(db(uid), `couples/${C}/watching/now`);

    it('saves YouTube videos only, single videos with an id', async () => {
      const add = (o) => addDoc(collection(db('alice'), `couples/${C}/videos`), video(o));
      await assertSucceeds(add());
      await assertSucceeds(add({ source: 'youtubeMusic', url: 'https://music.youtube.com/watch?v=BddP6PYo2gs' }));
      await assertFails(add({ source: 'spotify', url: 'https://open.spotify.com/track/abc', kind: 'track' }));
      await assertFails(add({ kind: 'playlist' }));
      await assertFails(add({ mediaId: '' }));
      await assertFails(add({ addedBy: 'bob' }));
      await assertFails(addDoc(collection(db('carol'), `couples/${C}/videos`), video({ addedBy: 'carol', lovedBy: {} })));
    });

    it('edits and plays like songs; the link never changes', async () => {
      const ref = await addDoc(collection(db('alice'), `couples/${C}/videos`), video());
      const bobRef = doc(db('bob'), `couples/${C}/videos/${ref.id}`);
      await assertSucceeds(updateDoc(bobRef, { title: 'Trailer', 'lovedBy.bob': true }));
      await assertSucceeds(updateDoc(bobRef, { playCount: increment(1) }));
      await assertFails(updateDoc(bobRef, { mediaId: 'AAAAAAAAAAA' }));
      await assertSucceeds(deleteDoc(bobRef));
    });

    it('a watch session syncs like listening, for YouTube only', async () => {
      await assertFails(setDoc(watching('alice'), session({ source: 'spotify' })));
      await assertFails(setDoc(watching('alice'), session({ mediaId: '' })));
      await assertSucceeds(setDoc(watching('alice'), session()));
      await assertSucceeds(updateDoc(watching('bob'), { status: 'paused', positionMs: 5000, updatedBy: 'bob', version: 2, updatedAt: serverTimestamp() }));
      await assertFails(updateDoc(watching('bob'), { status: 'playing', updatedBy: 'bob', version: 2, updatedAt: serverTimestamp() }));
      await assertSucceeds(updateDoc(watching('bob'), { 'listeners.bob': 1 }));
      await assertFails(getDoc(watching('carol')));
      await assertFails(deleteDoc(watching('alice')));
      const mine = doc(db('bob'), `couples/${C}/watching/clock-bob`);
      await assertSucceeds(setDoc(mine, { t: serverTimestamp() }));
      await assertFails(setDoc(doc(db('bob'), `couples/${C}/watching/clock-alice`), { t: serverTimestamp() }));
    });
  });
});
