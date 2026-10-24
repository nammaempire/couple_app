// Port of firestore-tests/test/storage.rules.test.js, plus the other paths in storage.rules.
import { after, before, beforeEach, describe, it } from "node:test";
import assert from "node:assert/strict";
import { authz, startApp } from "./helpers.js";

const { tx } = await import("../src/db.js");
const { adminPut } = await import("../src/store.js");
const { MemoryBucket, setBucket } = await import("../src/files.js");

const C = "couple1";
const MB = 1024 * 1024;
const bucket = new MemoryBucket();
setBucket(bucket);

let s: Awaited<ReturnType<typeof startApp>>;
before(async () => {
  s = await startApp();
});
after(async () => {
  await s.close();
});

const jpg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);
const enc = (p: string) => p.split("/").map(encodeURIComponent).join("/");

async function put(uid: string | null, path: string, type = "image/jpeg", bytes: Buffer = jpg, metadata?: Record<string, string>) {
  const res = await fetch(`${s.base}/v1/files/${enc(path)}`, {
    method: "PUT",
    headers: {
      "content-type": type,
      "content-length": String(bytes.length),
      ...(uid ? authz(uid) : {}),
      ...(metadata ? { "x-file-metadata": Buffer.from(JSON.stringify(metadata)).toString("base64url") } : {}),
    },
    body: bytes,
  });
  await res.arrayBuffer();
  return res.status;
}

async function read(uid: string, path: string) {
  const res = await fetch(`${s.base}/v1/files/url`, {
    method: "POST",
    headers: { "content-type": "application/json", ...authz(uid) },
    body: JSON.stringify({ path }),
  });
  await res.arrayBuffer();
  return res.status;
}

async function del(uid: string, path: string) {
  const res = await fetch(`${s.base}/v1/files/${enc(path)}`, { method: "DELETE", headers: authz(uid) });
  await res.arrayBuffer();
  return res.status;
}

const ok = (status: number) => assert.equal(status, 200);
const denied = (status: number) => assert.ok(status === 403 || status === 401, `expected denial, got ${status}`);

describe("storage rules", () => {
  beforeEach(async () => {
    bucket.objects.clear();
    await tx(async (c) => {
      await adminPut(c, `couples/${C}`, { memberIds: ["alice", "bob"], inviteCode: "ABC234" });
      await adminPut(c, "users/alice", { coupleId: C });
      await adminPut(c, "users/bob", { coupleId: C });
      await adminPut(c, "users/eve", { coupleId: null });
    });
  });

  it("shared backgrounds: both partners read, strangers cannot", async () => {
    ok(await put("alice", `couples/${C}/backgrounds/a.jpg`));
    ok(await read("bob", `couples/${C}/backgrounds/a.jpg`));
    denied(await read("eve", `couples/${C}/backgrounds/a.jpg`));
    denied(await put("eve", `couples/${C}/backgrounds/b.jpg`));
  });

  it("shared backgrounds must be images under 10 MB, and cannot be overwritten", async () => {
    denied(await put("alice", `couples/${C}/backgrounds/a.mp4`, "video/mp4"));
    denied(await put("alice", `couples/${C}/backgrounds/big.jpg`, "image/jpeg", Buffer.alloc(11 * MB)));
    ok(await put("alice", `couples/${C}/backgrounds/a.jpg`));
    denied(await put("alice", `couples/${C}/backgrounds/a.jpg`)); // create only
    ok(await del("bob", `couples/${C}/backgrounds/a.jpg`));
  });

  it("personal backgrounds are private to their owner", async () => {
    ok(await put("alice", "users/alice/backgrounds/a.jpg"));
    ok(await read("alice", "users/alice/backgrounds/a.jpg"));
    denied(await read("bob", "users/alice/backgrounds/a.jpg"));
    denied(await put("bob", "users/alice/backgrounds/x.jpg"));
    denied(await del("bob", "users/alice/backgrounds/a.jpg"));
    ok(await del("alice", "users/alice/backgrounds/a.jpg"));
  });

  it("unauthenticated requests are rejected", async () => {
    denied(await put(null, `couples/${C}/photos/a.jpg`));
  });

  it("chat photos, videos and voice: type and size limits, members only", async () => {
    ok(await put("alice", `couples/${C}/photos/p.jpg`));
    ok(await put("alice", `couples/${C}/photos/p.jpg`)); // write covers update
    denied(await put("alice", `couples/${C}/photos/p.pdf`, "application/pdf"));
    denied(await put("alice", `couples/${C}/photos/big.jpg`, "image/jpeg", Buffer.alloc(15 * MB)));
    ok(await put("alice", `couples/${C}/photos/edge.jpg`, "image/jpeg", Buffer.alloc(15 * MB - 1)));
    ok(await put("bob", `couples/${C}/videos/v.mp4`, "video/mp4"));
    denied(await put("bob", `couples/${C}/videos/v.jpg`, "image/jpeg"));
    ok(await put("bob", `couples/${C}/voice/a.m4a`, "audio/mp4"));
    denied(await put("bob", `couples/${C}/voice/big.m4a`, "audio/mp4", Buffer.alloc(10 * MB)));
    denied(await put("eve", `couples/${C}/voice/e.m4a`, "audio/mp4"));
    ok(await read("bob", `couples/${C}/photos/p.jpg`));
    denied(await del("eve", `couples/${C}/photos/p.jpg`));
    ok(await del("bob", `couples/${C}/photos/p.jpg`));
  });

  it("memories accept images and videos", async () => {
    ok(await put("alice", `couples/${C}/memories/m.jpg`));
    ok(await put("alice", `couples/${C}/memories/m.mp4`, "video/mp4"));
    ok(await put("alice", `couples/${C}/memories/m.mp4`, "video/mp4")); // update allowed
    denied(await put("alice", `couples/${C}/memories/m.m4a`, "audio/mp4"));
  });

  it("voice love letters: senderId metadata (mixed case) must be the uploader; only the sender reads or deletes", async () => {
    const path = `couples/${C}/notes/n1.m4a`;
    denied(await put("alice", path, "audio/mp4", jpg));
    denied(await put("alice", path, "audio/mp4", jpg, { senderId: "bob" }));
    ok(await put("alice", path, "audio/mp4", jpg, { senderId: "alice" }));
    denied(await put("alice", path, "audio/mp4", jpg, { senderId: "alice" })); // create only
    ok(await read("alice", path));
    denied(await read("bob", path));
    denied(await del("bob", path));
    ok(await del("alice", path));
    denied(await put("alice", `couples/${C}/notes/n2.jpg`, "image/jpeg", jpg, { senderId: "alice" }));
  });

  it("books are PDFs under 50 MB; vault files are octet-stream under 15 MB", async () => {
    ok(await put("alice", `couples/${C}/books/b.pdf`, "application/pdf"));
    denied(await put("alice", `couples/${C}/books/b2.pdf`, "application/x-pdf"));
    ok(await read("bob", `couples/${C}/books/b.pdf`));
    ok(await put("alice", `couples/${C}/vault/v.bin`, "application/octet-stream"));
    denied(await put("alice", `couples/${C}/vault/v2.bin`, "image/jpeg"));
    denied(await put("alice", `couples/${C}/vault/big.bin`, "application/octet-stream", Buffer.alloc(15 * MB)));
  });

  it("couple profile picture: members, image under 10 MB", async () => {
    ok(await put("bob", `couples/${C}/profile/p.jpg`));
    ok(await put("bob", `couples/${C}/profile/p.jpg`));
    denied(await put("bob", `couples/${C}/profile/p.gif`, "text/plain"));
    ok(await read("alice", `couples/${C}/profile/p.jpg`));
    denied(await read("eve", `couples/${C}/profile/p.jpg`));
  });

  it("user profile picture: owner writes, partner reads, strangers cannot", async () => {
    ok(await put("alice", "users/alice/profile/me.jpg"));
    denied(await put("bob", "users/alice/profile/me.jpg"));
    ok(await read("alice", "users/alice/profile/me.jpg"));
    ok(await read("bob", "users/alice/profile/me.jpg"));
    denied(await read("eve", "users/alice/profile/me.jpg"));
    denied(await del("bob", "users/alice/profile/me.jpg"));
    ok(await del("alice", "users/alice/profile/me.jpg"));
  });

  it("everything else is denied", async () => {
    denied(await put("alice", `couples/${C}/other/x.jpg`));
    denied(await put("alice", "random/x.jpg"));
    denied(await put("alice", `couples/${C}/photos/deep/x.jpg`));
    denied(await put("alice", "couples/nope/photos/x.jpg"));
  });

  it("download links serve the bytes when the bucket has no URLs of its own (in-memory)", async () => {
    ok(await put("alice", `couples/${C}/photos/p.jpg`));
    const res = await fetch(`${s.base}/v1/files/url`, {
      method: "POST",
      headers: { "content-type": "application/json", ...authz("bob") },
      body: JSON.stringify({ path: `couples/${C}/photos/p.jpg` }),
    });
    const { downloadUrl } = (await res.json()) as { downloadUrl: string };
    // PUBLIC_URL is http://test.local in tests; ask this server instead.
    const link = new URL(downloadUrl);
    const got = await fetch(`${s.base}${link.pathname}${link.search}`);
    assert.equal(got.status, 200);
    assert.equal(got.headers.get("content-type"), "image/jpeg");
    assert.deepEqual(Buffer.from(await got.arrayBuffer()), jpg);
    const bad = await fetch(`${s.base}${link.pathname}?t=nope`);
    await bad.arrayBuffer();
    denied(bad.status);
  });
});
