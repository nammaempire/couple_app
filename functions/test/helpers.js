// Shared setup for tests run under `firebase emulators:exec --only firestore,storage`.
// emulators:exec exports FIRESTORE_EMULATOR_HOST and FIREBASE_STORAGE_EMULATOR_HOST;
// we pin the project and default bucket the admin SDK would get from Cloud Functions.
const PROJECT = 'demo-couple';
const BUCKET = 'demo-couple.appspot.com';
process.env.GCLOUD_PROJECT = PROJECT;
process.env.FIREBASE_CONFIG = JSON.stringify({ projectId: PROJECT, storageBucket: BUCKET });
if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST) {
  throw new Error('Run via `npm test` (firebase emulators:exec --only firestore,storage).');
}

const { db, bucket } = require('../lib/admin.js');
const { Timestamp } = require('firebase-admin/firestore');

const DAY = 24 * 60 * 60 * 1000;
const ts = (msFromNow) => Timestamp.fromMillis(Date.now() + msFromNow);

async function clearAll() {
  const res = await fetch(
    `http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`,
    { method: 'DELETE' },
  );
  if (!res.ok) throw new Error(`clear firestore: ${res.status}`);
  await bucket().deleteFiles({ force: true }).catch(() => {});
}

async function putFile(path, body = 'x') {
  await bucket().file(path).save(Buffer.from(body), { resumable: false });
}

async function listFiles(prefix) {
  const [files] = await bucket().getFiles({ prefix });
  return files.map((f) => f.name).sort();
}

const PROFILE = {
  displayName: 'Alice', nickname: 'Al', photoUrl: 'https://x/p.jpg', birthday: '1998-02-03',
  phone: '+910000000000', email: 'a@example.com', avatar: { skin: 'skin4' }, avatarAsPhoto: true,
  notificationPrefs: { chat: true }, adultConfirmedAt: Timestamp.fromMillis(1700000000000),
};
const RELATIONSHIP = {
  chatLookMode: 'shared', chatLook: { bg: 'rose' }, chatClearedAt: Timestamp.fromMillis(1700000000000), mutePartner: true,
};

/** Seeds a couple with nested data, files, invites, pair requests and both users. */
async function seedCouple(cid, members = ['alice', 'bob'], extra = {}) {
  const f = db();
  await f.doc(`couples/${cid}`).set({ memberIds: members, inviteCode: `INV${cid}`, createdAt: ts(-30 * DAY), ...extra });
  const subs = ['messages', 'moods', 'memories', 'vault', 'vaultItems', 'calls', 'settings', 'futureThing2030'];
  for (const s of subs) {
    await f.doc(`couples/${cid}/${s}/a`).set({ v: 1 });
    await f.doc(`couples/${cid}/${s}/b`).set({ v: 2 });
  }
  await f.doc(`couples/${cid}/games/g1`).set({ kind: 'quiz' });
  await f.doc(`couples/${cid}/games/g1/secret/answers`).set({ alice: 'x' });
  await f.doc(`couples/${cid}/games/g1/secret/answers/deeper/x`).set({ y: 1 });
  // A subcollection under a doc that itself doesn't exist (only referenced by path).
  await f.doc(`couples/${cid}/ghostParent/missing/kids/k1`).set({ z: 1 });
  for (const uid of members) {
    await f.doc(`users/${uid}`).set({ ...PROFILE, displayName: uid, coupleId: cid, ...RELATIONSHIP });
    await putFile(`users/${uid}/backgrounds/bg.jpg`);
    await putFile(`users/${uid}/profile/me.jpg`);
  }
  for (const p of ['photos/1.jpg', 'videos/1.mp4', 'voice/1.m4a', 'memories/a/b.jpg', 'vault/secret.bin', 'backgrounds/x.png']) {
    await putFile(`couples/${cid}/${p}`);
  }
  await f.doc(`invites/INV${cid}`).set({ coupleId: cid, createdBy: members[0] });
  await f.doc(`pairRequests/pr_${cid}`).set({ coupleId: cid, from: members[0] });
}

async function countDocsUnder(path) {
  const ref = db().doc(path);
  let n = (await ref.get()).exists ? 1 : 0;
  for (const c of await ref.listCollections()) {
    for (const d of (await c.listDocuments())) n += await countDocsUnder(d.path);
  }
  return n;
}

module.exports = { PROJECT, BUCKET, DAY, ts, clearAll, putFile, listFiles, seedCouple, countDocsUnder, PROFILE, RELATIONSHIP, db, bucket };
