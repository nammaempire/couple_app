/**
 * End-to-end import from a fake Firestore + fake Storage into Postgres and a
 * MemoryBucket, through the same code path the CLI uses.
 */
import { after, before, describe, it } from "node:test";
import assert from "node:assert/strict";
import { Readable } from "node:stream";
import { Firestore, GeoPoint, Timestamp } from "firebase-admin/firestore";
import { startApp } from "./helpers.js";
import type { FirestoreSource, ImportOptions, SourceDoc, SourceObject, StorageSource } from "../scripts/import-lib.js";

const { runImport } = await import("../scripts/import-run.js");
const { MemoryBucket, downloadUrl, setBucket } = await import("../src/files.js");
const { pool } = await import("../src/db.js");

const BUCKET = "together-48033.firebasestorage.app";
const fbUrl = (path: string, bucket = BUCKET) =>
  `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/${encodeURIComponent(path)}?alt=media&token=abc-123`;

// ---- Fakes ---------------------------------------------------------------------------

interface FakeDoc {
  data: Record<string, unknown>;
  createTime: Date;
  updateTime: Date;
}

class FakeFirestore implements FirestoreSource {
  calls = { subcollections: 0 };
  constructor(public docs: Map<string, FakeDoc>, private pageSize = 2) {}

  private children(prefixSegs: string[]): string[] {
    const out = new Set<string>();
    for (const p of this.docs.keys()) {
      const segs = p.split("/");
      if (segs.length > prefixSegs.length && prefixSegs.every((s, i) => segs[i] === s)) out.add(segs[prefixSegs.length]);
    }
    return [...out].sort();
  }
  async rootCollections() {
    return this.children([]);
  }
  async subcollections(docPath: string) {
    this.calls.subcollections++;
    return this.children(docPath.split("/"));
  }
  async *documents(colPath: string): AsyncIterable<SourceDoc[]> {
    const ids = this.children(colPath.split("/"));
    for (let i = 0; i < ids.length; i += this.pageSize) {
      yield ids.slice(i, i + this.pageSize).map((id) => {
        const path = `${colPath}/${id}`;
        const d = this.docs.get(path);
        return d
          ? { path, exists: true, data: d.data, createTime: d.createTime, updateTime: d.updateTime }
          : { path, exists: false };
      });
    }
  }
}

class FakeStorage implements StorageSource {
  opened: string[] = [];
  constructor(public objects: Map<string, { bytes: Buffer; contentType: string; metadata: Record<string, string> }>) {}
  async *list(): AsyncIterable<SourceObject[]> {
    const all = [...this.objects.entries()].sort(([a], [b]) => a.localeCompare(b));
    for (let i = 0; i < all.length; i += 2) {
      yield all.slice(i, i + 2).map(([name, o]) => ({ name, size: o.bytes.length, contentType: o.contentType, metadata: o.metadata }));
    }
  }
  open(name: string) {
    this.opened.push(name);
    return Readable.from([this.objects.get(name)!.bytes]);
  }
}

// ---- Fixture ---------------------------------------------------------------------------

const t0 = new Date("2025-01-01T10:00:00.000Z");
const t1 = new Date("2025-01-02T11:30:00.123Z");
const fsRefs = new Firestore({ projectId: "demo" });

function fixture(): Map<string, FakeDoc> {
  const d = (data: Record<string, unknown>, createTime = t0, updateTime = t1): FakeDoc => ({ data, createTime, updateTime });
  return new Map([
    ["users/u1", d({ name: "Asha", coupleId: "c1", photoUrl: fbUrl("users/u1/profile/me.jpg"), lastSeen: Timestamp.fromDate(t1) })],
    ["users/u2", d({ name: "Ravi", coupleId: "c1", $internal: true })],
    ["users/u1/devices/d1", d({ token: "fcm-1", platform: "android" })],
    // users/u3 doesn't exist; only its subcollection does.
    ["users/u3/devices/d9", d({ token: "orphan" })],
    ["couples/c1", d({ memberIds: ["u1", "u2"], photoUrl: fbUrl("couples/c1/profile/us.jpg"), owner: fsRefs.doc("users/u1") })],
    [
      "couples/c1/messages/m1",
      d({
        senderId: "u1",
        type: "image",
        sentAt: Timestamp.fromDate(t1),
        imageUrl: fbUrl("couples/c1/photos/p1.jpg"),
        media: [{ url: `gs://${BUCKET}/couples/c1/videos/v1.mp4`, thumbUrl: fbUrl("couples/c1/photos/t1.jpg") }],
        where: new GeoPoint(12.97, 77.59),
        foreign: fbUrl("x/y.jpg", "other-project.appspot.com"),
      }),
    ],
    ["couples/c1/messages/m2", d({ senderId: "u2", type: "text", text: "hi", sentAt: Timestamp.fromDate(t0) })],
    ["couples/c1/messages/m3", d({ senderId: "u2", type: "voice", voiceUrl: fbUrl("couples/c1/voice/v1.m4a"), blob: Buffer.from([1, 2, 3]) })],
    ["couples/c1/notes/n1", d({ fromUid: "u1", deliverAt: Timestamp.fromDate(t1) })],
    ["couples/c1/notes/n1/sealed/content", d({ body: "secret", voiceUrl: fbUrl("couples/c1/notes/n1.m4a") })],
    ["couples/c1/games/g1/secret/u1", d({ word: "mango" })], // games/g1 itself is missing
    ["phoneIndex/+919999999999", d({ uid: "u1" })],
    ["legacyLogs/l1", d({ msg: "old" })],
    ["legacyLogs/l1/entries/e1", d({ msg: "older" })],
    ["couples/c1/unknownSub/x1", d({ a: 1 })],
  ]);
}

function storageFixture() {
  const o = (s: string, contentType: string, metadata: Record<string, string> = {}) => ({ bytes: Buffer.from(s), contentType, metadata });
  return new Map([
    ["users/u1/profile/me.jpg", o("me-jpeg", "image/jpeg", { firebaseStorageDownloadTokens: "abc-123" })],
    ["couples/c1/profile/us.jpg", o("us-jpeg", "image/jpeg")],
    ["couples/c1/photos/p1.jpg", o("p1-jpeg-bytes", "image/jpeg")],
    ["couples/c1/photos/t1.jpg", o("t1", "image/jpeg")],
    ["couples/c1/videos/v1.mp4", o("video-bytes-here", "video/mp4")],
    ["couples/c1/notes/n1.m4a", o("voice-note", "audio/mp4", { senderId: "u1" })],
    ["couples/c1/photos/", o("", "application/x-directory")],
  ]);
}

const opts = (o: Partial<ImportOptions> = {}): ImportOptions => ({
  dryRun: false,
  only: "all",
  collections: [],
  verbose: false,
  concurrency: 4,
  help: false,
  ...o,
});

async function rows(table: string) {
  return (await pool.query(`SELECT * FROM "${table}" ORDER BY 1, 2`)).rows;
}

async function count(table: string): Promise<number> {
  return Number((await pool.query(`SELECT count(*) FROM "${table}"`)).rows[0].count);
}

// ---- Tests ----------------------------------------------------------------------------

describe("import from Firebase", () => {
  let s: Awaited<ReturnType<typeof startApp>>;
  let target: InstanceType<typeof MemoryBucket>;
  let fs: FakeFirestore;
  let st: FakeStorage;
  const logs: string[] = [];
  const deps = () => ({ firestore: fs, storage: st, target, sourceBucket: BUCKET, toUrl: downloadUrl, log: (l: string) => logs.push(l) });

  before(async () => {
    s = await startApp();
    target = new MemoryBucket();
    setBucket(target);
    fs = new FakeFirestore(fixture());
    st = new FakeStorage(storageFixture());
  });
  after(async () => {
    await s.close();
  });

  it("dry run reads everything and writes nothing", async () => {
    const sum = await runImport(opts({ dryRun: true }), deps());
    assert.equal(sum.fatal, undefined);
    assert.equal(sum.tables.couple_messages.inserted, 3);
    assert.equal(sum.files.copied, 6);
    assert.equal(await count("users"), 0);
    assert.equal(await count("couple_messages"), 0);
    assert.equal(target.objects.size, 0);
  });

  it("copies documents and files", async () => {
    const sum = await runImport(opts(), deps());
    assert.equal(sum.fatal, undefined, sum.fatal);

    // Per-table counts.
    assert.deepEqual(sum.tables.users, { inserted: 2, updated: 0, unchanged: 0 });
    assert.deepEqual(sum.tables.user_devices, { inserted: 2, updated: 0, unchanged: 0 });
    assert.equal(sum.tables.couple_messages.inserted, 3);
    assert.equal(sum.tables.couple_note_sealed.inserted, 1);
    assert.equal(sum.tables.couple_game_secrets.inserted, 1);
    assert.equal(sum.tables.phone_index.inserted, 1);
    assert.equal(sum.missingParents, 2); // users/u3, couples/c1/games/g1

    // Unknown paths are skipped, not fatal.
    assert.deepEqual(Object.keys(sum.skipped).sort(), ["couples/{id}/unknownSub/{id}", "legacyLogs/{id}", "legacyLogs/{id}/entries/{id}"]);

    // Row shape: parent ids, data, Firestore times.
    const users = await rows("users");
    assert.equal(users.length, 2);
    const u1 = users.find((r) => r.id === "u1")!;
    assert.equal(u1.create_time, t0.toISOString());
    assert.equal(u1.update_time, t1.toISOString());
    assert.deepEqual(u1.data.lastSeen, { $ts: t1.toISOString() });
    assert.equal(u1.data.photoUrl, downloadUrl("users/u1/profile/me.jpg"));
    assert.ok(!("$internal" in (users.find((r) => r.id === "u2")!.data as object)));
    assert.ok(sum.warnings.some((w) => w.includes("users/u2") && w.includes("$internal")));

    const sealed = await rows("couple_note_sealed");
    assert.equal(sealed.length, 1);
    assert.equal(sealed[0].couple_id, "c1");
    assert.equal(sealed[0].note_id, "n1");
    assert.equal(sealed[0].id, "content");
    assert.equal(sealed[0].data.voiceUrl, downloadUrl("couples/c1/notes/n1.m4a"));

    const orphan = (await rows("user_devices")).find((r) => r.id === "d9")!;
    assert.equal(orphan.user_id, "u3");

    const m1 = (await rows("couple_messages")).find((r) => r.id === "m1")!;
    assert.equal(m1.data.imageUrl, downloadUrl("couples/c1/photos/p1.jpg"));
    assert.deepEqual(m1.data.media, [{ url: downloadUrl("couples/c1/videos/v1.mp4"), thumbUrl: downloadUrl("couples/c1/photos/t1.jpg") }]);
    assert.deepEqual(m1.data.where, { latitude: 12.97, longitude: 77.59 });
    assert.deepEqual(m1.data.sentAt, { $ts: t1.toISOString() });
    assert.equal(m1.data.foreign, fbUrl("x/y.jpg", "other-project.appspot.com"));
    const m3 = (await rows("couple_messages")).find((r) => r.id === "m3")!;
    assert.equal(m3.data.blob, Buffer.from([1, 2, 3]).toString("base64"));

    const c1 = (await rows("couples"))[0];
    assert.equal(c1.data.owner, "users/u1");

    assert.equal(sum.urlsRewritten, 7);
    assert.equal(sum.foreignUrls, 1);
    assert.deepEqual(sum.linksToMissingFiles, ["couples/c1/voice/v1.m4a"]);

    // Files: same keys, content type, lower-cased metadata, token dropped.
    assert.equal(sum.files.copied, 6);
    assert.equal(sum.files.skipped, 1); // folder placeholder
    assert.equal(sum.files.failed, 0);
    assert.equal(target.objects.size, 6);
    const note = target.objects.get("couples/c1/notes/n1.m4a")!;
    assert.equal(note.bytes.toString(), "voice-note");
    assert.equal(note.meta.contentType, "audio/mp4");
    assert.deepEqual(note.meta.metadata, { senderid: "u1" });
    assert.deepEqual(target.objects.get("users/u1/profile/me.jpg")!.meta.metadata, {});

    // The rewritten links are valid on the server.
    const res = await fetch(`${s.base}${new URL(m1.data.imageUrl).pathname}${new URL(m1.data.imageUrl).search}`, { redirect: "manual" });
    // The in-memory bucket serves the bytes itself; a real bucket redirects.
    assert.ok([200, 302].includes(res.status), String(res.status));
    if (res.status === 302) assert.equal(res.headers.get("location"), "memory://couples/c1/photos/p1.jpg");
  });

  it("a second run changes nothing", async () => {
    const before = await pool.query(`SELECT id, version FROM couple_messages ORDER BY id`);
    st.opened = [];
    const sum = await runImport(opts(), deps());
    assert.equal(sum.fatal, undefined);
    for (const [t, c] of Object.entries(sum.tables)) {
      assert.equal(c.inserted + c.updated, 0, `${t} was rewritten`);
    }
    assert.equal(sum.tables.couple_messages.unchanged, 3);
    assert.equal(sum.files.copied, 0);
    assert.equal(sum.files.skipped, 7);
    assert.deepEqual(st.opened, []);
    const after = await pool.query(`SELECT id, version FROM couple_messages ORDER BY id`);
    assert.deepEqual(after.rows, before.rows);
  });

  it("re-runs pick up newer Firestore data but keep rows changed in the new backend", async () => {
    // Changed in Firestore after the first import.
    const t2 = new Date("2025-01-05T00:00:00.000Z");
    fs.docs.set("couples/c1/messages/m2", { data: { senderId: "u2", type: "text", text: "edited" }, createTime: t0, updateTime: t2 });
    // Changed in the new backend after the import (update_time = now).
    await pool.query(`UPDATE users SET data = data || '{"name":"Asha K"}', update_time = now() WHERE id = 'u1'`);
    // A file that changed size.
    st.objects.get("couples/c1/photos/t1.jpg")!.bytes = Buffer.from("t1-bigger");

    const sum = await runImport(opts(), deps());
    assert.equal(sum.fatal, undefined);
    assert.equal(sum.tables.couple_messages.updated, 1);
    assert.equal(sum.tables.users.updated, 0);
    const m2 = (await rows("couple_messages")).find((r) => r.id === "m2")!;
    assert.equal(m2.data.text, "edited");
    assert.equal(m2.update_time, t2.toISOString());
    assert.equal((await rows("users")).find((r) => r.id === "u1")!.data.name, "Asha K");
    assert.equal(sum.files.copied, 1);
    assert.equal(target.objects.get("couples/c1/photos/t1.jpg")!.bytes.toString(), "t1-bigger");
  });

  it("--collection and --only limit the run", async () => {
    const sum = await runImport(opts({ only: "firestore", collections: ["phoneIndex"] }), deps());
    assert.equal(sum.fatal, undefined);
    assert.deepEqual(Object.keys(sum.tables), ["phone_index"]);
    assert.equal(sum.docsRead, 1);
    assert.equal(sum.files.listed, 0);
  });

  it("reports a failing file and keeps going", async () => {
    const failing = new FakeStorage(new Map([["couples/c1/photos/bad.jpg", { bytes: Buffer.from("x"), contentType: "image/jpeg", metadata: {} }]]));
    failing.open = () =>
      new Readable({
        read() {
          this.destroy(new Error("network down"));
        },
      });
    const sum = await runImport(opts({ only: "storage" }), { ...deps(), storage: failing });
    assert.equal(sum.fatal, undefined);
    assert.equal(sum.files.failed, 1);
    assert.ok(sum.warnings.some((w) => w.includes("network down")));
  });
});
