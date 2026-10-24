/**
 * Shared setup for functions-*.test.ts (port of functions/test/helpers.js).
 * Import "./helpers.js" first so the test env is set before config loads.
 */
import assert from "node:assert/strict";
import { Readable } from "node:stream";
import { call } from "./helpers.js";

const { tx, pool } = await import("../src/db.js");
const { adminGet, adminPut, adminDelete, adminWrite } = await import("../src/store.js");
const { COLLECTIONS, quoteIdent } = await import("../src/schema.js");
const { getBucket, MemoryBucket, setBucket } = await import("../src/files.js");
const { tsMillis } = await import("../src/values.js");

export const DAY = 24 * 60 * 60 * 1000;
export const ts = (msFromNow: number) => ({ $ts: new Date(Date.now() + msFromNow).toISOString() });
export const tsAt = (ms: number) => ({ $ts: new Date(ms).toISOString() });
export const millis = (v: unknown) => {
  const n = tsMillis(v);
  assert.notEqual(n, null, `not a timestamp: ${JSON.stringify(v)}`);
  return n!;
};
export const isTimestamp = (v: unknown) => tsMillis(v) !== null;

export const bucket = new MemoryBucket();
setBucket(bucket);

export async function clearAll(): Promise<void> {
  await pool.query(`TRUNCATE ${COLLECTIONS.map((d) => quoteIdent(d.table)).join(", ")}`);
  bucket.objects.clear();
}

export async function putFile(path: string, body = "x"): Promise<void> {
  const buf = Buffer.from(body);
  await getBucket().put(path, Readable.from([buf]), buf.length, "application/octet-stream", {});
}

export async function listFiles(prefix: string): Promise<string[]> {
  return [...bucket.objects.keys()].filter((k) => k.startsWith(prefix)).sort();
}

export async function get(path: string): Promise<any> {
  const d = await adminGet(pool, path);
  return d.exists ? d.data : undefined;
}
export const exists = async (path: string) => (await adminGet(pool, path)).exists;

export async function set(path: string, data: Record<string, unknown>): Promise<void> {
  await tx((c) => adminWrite(c, { op: "set", path, data: data as any }));
}
export async function update(path: string, data: Record<string, unknown>): Promise<void> {
  await tx((c) => adminWrite(c, { op: "update", path, data: data as any }));
}
export async function del(path: string): Promise<void> {
  await tx((c) => adminDelete(c, path));
}
export { adminPut };

/** Documents of the couple and everything nested under it. */
export async function countDocsUnder(cid: string): Promise<number> {
  let n = (await exists(`couples/${cid}`)) ? 1 : 0;
  for (const d of COLLECTIONS) {
    if (!d.pattern.startsWith("couples/{coupleId}/")) continue;
    const r = await pool.query<{ n: number }>(
      `SELECT count(*)::int AS n FROM ${quoteIdent(d.table)} WHERE ${quoteIdent(d.parentCols[0])} = $1`,
      [cid],
    );
    n += r.rows[0].n;
  }
  return n;
}

export const PROFILE = {
  displayName: "Alice",
  nickname: "Al",
  photoUrl: "https://x/p.jpg",
  birthday: "1998-02-03",
  phone: "+910000000000",
  email: "a@example.com",
  avatar: { skin: "skin4" },
  avatarAsPhoto: true,
  notificationPrefs: { chat: true },
  adultConfirmedAt: tsAt(1700000000000),
};
export const RELATIONSHIP = {
  chatLookMode: "shared",
  chatLook: { bg: "rose" },
  chatClearedAt: tsAt(1700000000000),
  mutePartner: true,
};

/** Known subcollections seeded with two docs each (Postgres only has known tables). */
export const SEEDED_SUBS = ["messages", "moods", "memories", "vault", "vaultItems", "call", "settings", "songs"];

/** Seeds a couple with nested data, files, invites, pair requests and both users. */
export async function seedCouple(cid: string, members = ["alice", "bob"], extra: Record<string, unknown> = {}) {
  await set(`couples/${cid}`, { memberIds: members, inviteCode: `INV${cid}`, createdAt: ts(-30 * DAY), ...extra });
  for (const s of SEEDED_SUBS) {
    await set(`couples/${cid}/${s}/a`, { v: 1 });
    await set(`couples/${cid}/${s}/b`, { v: 2 });
  }
  await set(`couples/${cid}/games/g1`, { kind: "quiz" });
  await set(`couples/${cid}/games/g1/secret/answers`, { alice: "x" });
  // A nested doc under a parent that itself doesn't exist (only referenced by path).
  await set(`couples/${cid}/games/missing/secret/k1`, { z: 1 });
  for (const uid of members) {
    await set(`users/${uid}`, { ...PROFILE, displayName: uid, coupleId: cid, ...RELATIONSHIP });
    await putFile(`users/${uid}/backgrounds/bg.jpg`);
    await putFile(`users/${uid}/profile/me.jpg`);
  }
  for (const p of ["photos/1.jpg", "videos/1.mp4", "voice/1.m4a", "memories/a/b.jpg", "vault/secret.bin", "backgrounds/x.png"]) {
    await putFile(`couples/${cid}/${p}`);
  }
  await set(`invites/INV${cid}`, { coupleId: cid, createdBy: members[0] });
  await set(`pairRequests/pr_${cid}`, { coupleId: cid, from: members[0] });
}

export interface FnError {
  status: number;
  code: string;
  message: string;
  details?: any;
}

/** Calls POST /v1/fn/<name> like the app; resolves with result, rejects with {status, code, message, details}. */
export async function fn(base: string, name: string, uid: string | null, data: unknown): Promise<any> {
  const r = await call(base, `/v1/fn/${name}`, { data }, uid ?? undefined);
  if (r.json?.error) throw { status: r.status, ...r.json.error } as FnError;
  assert.equal(r.status, 200);
  return r.json.result;
}

export async function rejectsWith(promise: Promise<unknown>, code: string, re?: RegExp): Promise<any> {
  let err: any;
  await assert.rejects(promise, (e: any) => {
    assert.equal(e.code, code, `expected ${code}, got ${e.code}: ${e.message}`);
    if (re) assert.match(e.message, re);
    err = e;
    return true;
  });
  return err;
}
