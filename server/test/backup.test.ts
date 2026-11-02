/** Daily database backups: make, read, encrypt, prune, restore. */
import { after, before, beforeEach, describe, it } from "node:test";
import assert from "node:assert/strict";
import { startApp } from "./helpers.js";

const h = await import("./functions-helpers.js");
const b = await import("../src/ops/backup.js");
const { pool } = await import("../src/db.js");

process.env.FUNCTIONS_LOG = "off";
let s: Awaited<ReturnType<typeof startApp>>;
before(async () => {
  s = await startApp();
});
after(async () => {
  await s.close();
});

const DAY = 24 * 60 * 60 * 1000;

async function seed() {
  await h.seedCouple("c1");
  await h.set("couples/c1/messages/m1", { senderId: "alice", text: "hi ❤️", sentAt: h.ts(-1000), seen: false });
  await h.set("phoneIndex/+919000000001", { uid: "alice" });
}

async function snapshot() {
  const r = await pool.query<{ path: string }>(
    "SELECT count(*)::int AS n FROM couple_messages",
  );
  return {
    message: await h.get("couples/c1/messages/m1"),
    couple: await h.get("couples/c1"),
    phone: await h.get("phoneIndex/+919000000001"),
    messages: (r.rows[0] as unknown as { n: number }).n,
  };
}

describe("backups", () => {
  beforeEach(h.clearAll);

  it("backs up every table and restores it exactly", async () => {
    await seed();
    const before = await snapshot();
    const r = await b.runBackup({ now: new Date("2026-11-02T21:30:00Z"), passphrase: "" });
    assert.equal(r.key, "backups/db/2026-11-02T21-30-00Z.jsonl.gz");
    assert.equal(r.encrypted, false);
    assert.ok(r.tables.couples >= 1 && r.tables.couple_messages >= 1);
    assert.deepEqual((await b.listBackups()).map((x) => x.key), [r.key]);

    const contents = b.readBackup(await backupBytes(r), "");
    // Lose everything, then restore.
    await h.clearAll();
    const restored = await b.restoreBackup(contents);
    assert.equal(restored.tables.couple_messages, before.messages);
    assert.deepEqual(await snapshot(), before);
  });

  it("encrypts with BACKUP_ENCRYPTION_KEY; the wrong key can't read it", async () => {
    await seed();
    const r = await b.runBackup({ now: new Date("2026-11-02T21:30:00Z"), passphrase: "correct horse" });
    assert.ok(r.key.endsWith(".jsonl.gz.enc"));
    const bytes = await backupBytes(r);
    assert.doesNotMatch(bytes.toString("latin1"), /alice/);
    assert.throws(() => b.readBackup(bytes, ""), /encrypted/);
    assert.throws(() => b.readBackup(bytes, "wrong"), /Wrong BACKUP_ENCRYPTION_KEY/);
    const c = b.readBackup(bytes, "correct horse");
    assert.equal(c.rows.get("couple_messages")?.length, r.tables.couple_messages);
    assert.ok(JSON.stringify(c.rows.get("couple_messages")).includes("hi ❤️"));
  });

  it("refuses to restore over data unless told to replace it", async () => {
    await seed();
    const r = await b.runBackup({ passphrase: "" });
    const contents = b.readBackup(await backupBytes(r), "");
    await h.set("couples/c1/messages/m1", { senderId: "alice", text: "changed later" });
    await assert.rejects(b.restoreBackup(contents), /isn't empty/);
    await b.restoreBackup(contents, { replace: true });
    assert.equal((await h.get("couples/c1/messages/m1")).text, "hi ❤️");
  });

  it("keeps 30 days of backups, and always the newest", async () => {
    const now = new Date("2026-11-30T00:00:00Z");
    for (const daysAgo of [45, 31, 29, 1]) {
      await h.putFile(b.backupKey(new Date(now.getTime() - daysAgo * DAY), false), "x");
    }
    await h.putFile("backups/db/notes.txt", "not a backup");
    assert.equal(await b.pruneBackups(h.bucket, now, 30), 2);
    assert.deepEqual(
      (await b.listBackups()).map((x) => x.at.toISOString()),
      ["2026-11-01T00:00:00.000Z", "2026-11-29T00:00:00.000Z"],
    );
    // A lone old backup is kept rather than leaving none.
    await h.clearAll();
    await h.putFile(b.backupKey(new Date(now.getTime() - 90 * DAY), false), "x");
    assert.equal(await b.pruneBackups(h.bucket, now, 30), 0);
  });

  it("the hourly check backs up only when the last one is a day old", async () => {
    await seed();
    const t0 = new Date("2026-11-02T21:30:00Z");
    assert.ok(await b.runBackupTick(t0));
    assert.equal(await b.runBackupTick(new Date(t0.getTime() + 6 * 60 * 60 * 1000)), null);
    assert.ok(await b.runBackupTick(new Date(t0.getTime() + DAY)));
    assert.equal((await b.listBackups()).length, 2);
  });

  it("/health/backup says when backups have stopped", async () => {
    let res = await fetch(`${s.base}/health/backup`);
    assert.equal(res.status, 503, "no backup yet");
    await b.runBackup({ passphrase: "" });
    res = await fetch(`${s.base}/health/backup`);
    assert.equal(res.status, 200);
    const body = (await res.json()) as { ok: boolean; count: number; ageHours: number };
    assert.equal(body.ok, true);
    assert.equal(body.count, 1);
    assert.ok(body.ageHours < 1);
    // Stale after 36 hours.
    const later = await b.backupHealth(new Date(Date.now() + 37 * 60 * 60 * 1000));
    assert.equal(later.ok, false);
  });

  it("backups can't be reached through the files API", async () => {
    const r = await b.runBackup({ passphrase: "" });
    const res = await fetch(`${s.base}/v1/files/url`, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: "Bearer test:alice" },
      body: JSON.stringify({ path: r.key }),
    });
    assert.ok(res.status === 403 || res.status === 404, `got ${res.status}`);
  });
});

async function backupBytes(r: { key: string }): Promise<Buffer> {
  const bytes = await h.bucket.getBytes(r.key);
  assert.ok(bytes, "backup in the bucket");
  return bytes!;
}
